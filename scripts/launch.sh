#!/bin/bash

# MIT License - Copyright (c) Hydra Dynamix 2025  (https://github.com/hydra-dynamix/synthia)

set -e

burn_fee=2.5
source_miner="src/synthia/miner/template_miner.py"
source_validator="../synthia/validator/text_validator.py"

# Error handling
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Error handler function
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5

    echo "Error occurred in script at line: $line_no"
    echo "Command: $last_command"
    echo "Exit code: $exit_code"
    
    # Cleanup any running processes
    cleanup
    
    exit "$exit_code"
}

# Cleanup function
cleanup() {
    # Kill any running pm2 processes if they exist
    if command -v pm2 &> /dev/null; then
        pm2 delete all &> /dev/null || true
    fi
    
    # Return to original directory if we changed it
    if [ -n "$ORIGINAL_DIR" ]; then
        cd "$ORIGINAL_DIR" || exit
    fi
}

# Store original directory
ORIGINAL_DIR="$PWD"

# Check required commands
check_requirements() {
    local missing_requirements=0
    
    # Check for required commands
    for cmd in python3 pip3 curl; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is required but not installed."
            missing_requirements=1
        fi
    done
    
    if [ $missing_requirements -eq 1 ]; then
        echo "Please install missing requirements and try again."
        exit 1
    fi
}

# Function to create miner/validator files
create_module_files() {
    local module_type=$1  # "miner" or "validator"
    local filename=$2
    local classname=$3
    
    echo "Creating $module_type module files..."
    
    local source_file="src/synthia/$module_type/$filename.py"
    if [ ! -f "$source_file" ]; then
        local template_file
        if [ "$module_type" = "miner" ]; then
            template_file="$source_miner"
        else
            template_file="$source_validator"
        fi
        
        # Create directory if it doesn't exist
        mkdir -p "src/synthia/$module_type"
        
        # Copy template and replace class name
        cp "$template_file" "$source_file"
        sed -i "s/${module_type^}_1/$classname/g" "$source_file"
        echo "$module_type module created at $source_file"
    fi
}

# Install Synthia
install_synthia() {
    echo "Installing Synthia"
    
    # Move to the root directory of the project if we're in scripts
    if [[ "$PWD" == */scripts ]]; then
        cd ..
    fi

    if [ ! -x "/usr/bin/python3" ]; then
        echo "Python 3 is not installed. Please install Python 3 and try again."
        exit 1
    fi
    if [ ! -x "/usr/bin/pip3" ]; then
        echo "Python 3 is not installed. Please install Python 3 and try again."
        exit 1
    fi

    # Setting up virtual environment
    python3 -m venv .venv
    # shellcheck source=/dev/null
    source ".venv/bin/activate"
    python3 -m pip install --upgrade pip
    pip3 install setuptools wheel gnureadline

    # Installing poetry and setting up shell
    # shellcheck disable=SC2162
    curl -sSL https://install.python-poetry.org | python3 -
    echo "PATH=~/.local/share/pypoetry/venv/bin/poetry:$PATH" >>~/.bashrc
    echo "PATH=~/.local/bin:$PATH" >>~/.bashrc
    # shellcheck source=/dev/null
    source ~/.bashrc
    # shellcheck source=/dev/null
    source .venv/bin/activate

    # Installing dependencies
    poetry install

    # Installing synthia
    poetry run pip3 install -e .

    # Installing communex
    poetry run pip3 install --upgrade communex
    echo "Synthia installed."
}

# Sets up the environment for the miner or validator
create_setup() {
    echo "This will walk you through configuring your setup to launch miners and validators on CommuneAI."
    echo "The instillation will only work on Linux. If you are on Windows, please refer to the Synthia readme for instructions."
    echo "https://github.com/agicommies/synthia/blob/main/README.md"
    # shellcheck disable=SC2162
    read -p "Install Synthia (y/n): " install_synthia
    if [ "$install_synthia" = "y" ]; then
        install_synthia
    fi

    echo "Setting up environment"
    cp env/config.env.sample env/config.env
    echo "An environment file has been created in env/config.env. For your miner and validators to function you need an OpenAI API key and Anthropic API key."
    echo "OpenAI API key: https://platform.openai.com/api-keys"
    echo "Anthropic API key: https://console.anthropic.com/settings/keys"
    echo Setup complete.
}

# Function to configure the module launch
configure_launch() {
    # Enter the path of the module
    echo "The module name should be in the format of \"Namespace.Miner_X\" (eg. Rabbit.Miner_0)"
    # shellcheck disable=SC2162
    read -p "Module name: " key_name

    # Check if the module path is valid
    if [ "$key_name" = "" ]; then
        echo "Error, must provide a valid module name."
        # shellcheck disable=SC2162
        read -p "Module name: " key_name
    elif [ -z "$key_name" ]; then
        echo "Error, must provide a valid module name."
        exit 1
    fi

    # Extract the namespace for module path
    local namespace="${key_name%%.*}"
    local module_path="synthia.miner.${namespace}"

    # Enter the IP and port of the module
    while true; do
        # shellcheck disable=SC2162
        read -p "Module IP address for registration (the IP other nodes will use to connect to this miner): " registration_host
        if [ -z "$registration_host" ]; then
            echo "You must provide an IP address that other nodes can use to connect to this miner"
            continue
        fi
        if validate_ip "$registration_host"; then
            break
        fi
        echo "Please enter a valid IP address"
    done

    while true; do
        # shellcheck disable=SC2162
        read -p "Module port (default 10001): " port
        [ -z "$port" ] && port=10001
        validate_port "$port" && break
    done

    # Enter the netuid of the module with validation
    while true; do
        # shellcheck disable=SC2162
        read -p "Deploying to subnet (default 10): " netuid
        [ -z "$netuid" ] && netuid=10
        validate_number "$netuid" 0 100 && break
        echo "Please enter a valid subnet number (0-100)"
    done

    #    # Enter the name of the key that will be used to stake the validator
    #    echo "The name of the key that will be used to stake the validator. Defaults to Module Path ($module_path) if not provided."
    #    # shellcheck disable=SC2162
    #    read -p "Module key name: " key_name
    #    if [ "$key_name" = "" ]; then
    key_name=$key_name
    #    fi
    #    echo "Module key name: $key_name"
    #    echo ""

    if [ ! -f "$HOME/.commune/key/$key_name.json" ]; then
        create_key
    fi
    echo ""

    # Select if a balance needs to be transfered to the key
    echo "Transfer staking balance to the module key."
    echo "You can skip this step if you have enough balance on your key."
    echo "The sending key must be in the ~/.commune/key folder with enough com to transfer."
    # shellcheck disable=SC2162
    read -p "Transfer balance (y/n): " transfer_balance
    if [ "$transfer_balance" = "y" ]; then
        transfer_balance
    fi
    echo ""

    # Check if the module needs to be staked
    if [ "$needs_stake" = "true" ]; then
        echo "Set the stake. This is the amount of tokens that will be staked by the module."
        echo "Validators require a balance of 5200, not including fees, to vote."
        echo "Miners require a balance of 256, not including fees, to mine."
        echo "There will be a burn fee that starts at 10 com and scales based on demand"
        echo "will be burned as a fee to stake. Make sure you have enough to cover the cost."
        # shellcheck disable=SC2162
        read -p "Set stake: " stake
        echo "Setting stake: $stake"
        echo ""
    fi

    # Enter the delegation fee
    if [ "$is_update" = "true" ]; then
        echo "Set the delegation fee. This the percentage of the emission that are collected as a fee to delegate the staked votes to the module."
        # shellcheck disable=SC2162
        read -p "Delegation fee (default 20) int: " delegation_fee
        echo ""
    fi

    # Check it is above minimum
    if [ "$delegation_fee" -lt 5 ] || [ "$delegation_fee" = "" ]; then
        echo "Minimum delegation fee is 5%. Setting to 5%"
        delegation_fee=5
        echo "Module delegation fee: $delegation_fee"
        echo ""
    fi

    # Enter the metadata
    if [ "$is_update" = "true" ]; then
        echo "Set the metadata. This is an optional field."
        echo "It is a JSON object that is passed to the module in the format:"
        echo "{\"key\": \"value\"}."
        # shellcheck disable=SC2162

        read -p "Add metadata (y/n): " choose_metadata
        if [ "$choose_metadata" = "y" ]; then
            # shellcheck disable=SC2162
            read -p "Enter metadata object: " metadata
            echo "Module metadata: $metadata"
        fi
        echo ""
    fi

    # Confirm settings
    echo "Confirm module settings:"
    echo "Module path:        $module_path"
    echo "Module IP address for registration:  $registration_host"
    echo "Module port:        $port"
    echo "Module netuid:      $netuid"
    echo "Module key name:    $key_name"
    if [ "$needs_stake" = "true" ]; then
        echo "Module stake:       $stake"
    fi
    if [ "$is_update" = "true" ]; then
        echo "Delegation fee:     $delegation_fee"
        echo "Metadata:           $metadata"
    fi
    # shellcheck disable=SC2162
    read -p "Confirm settings (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        echo "Deploying..."
        echo ""
    else
        echo "Aborting..."
        exit 1
    fi

    # Export the variables for use in the bash script
    export MODULE_PATH="$module_path"
    export MODULE_IP="0.0.0.0"  # Always use 0.0.0.0 for serving
    export MODULE_REGISTRATION_IP="$registration_host"  # Use real IP for registration
    export MODULE_PORT="$port"
    export MODULE_NETUID="$netuid"
    export MODULE_KEYNAME="$key_name"
    export MODULE_STAKE="$stake"
    export MODULE_DELEGATION_FEE="$delegation_fee"
    export MODULE_METADATA="$metadata"
}

# Function to create a key
create_key() {
    echo "Creating key"
    echo "This creates a json key in ~/.commune/key with the given name."
    echo "Once you create the key you will want to save the mnemonic somewhere safe."
    echo "The mnemonic is the only way to recover your key if it lost then the key is unrecoverable."
    echo "Note that commune does not encrypt the key file so do not fund a key on an unsafe machine."

    if [ -z "$key_name" ]; then
        # shellcheck disable=SC2162
        read -p "Key name: " key_name
    fi
    comx key create "$key_name"
    echo "This is your key. Save the mnemonic somewhere safe."
    cat ~/.commune/key/"$key_name".json
    echo "$key_name created and saved at ~/.commune/key/$key_name.json"
}

# Function to perform a balance transfer
transfer_balance() {
    echo "Initiating Balance Transfer"
    echo "There is a 2.5 com fee on the balance of the transfer."
    echo "Example: 300 com transfered will arrive as 297.5 com"
    # shellcheck disable=SC2162
    read -p "From Key (sender): " key_from
    # shellcheck disable=SC2162
    read -p "Amount to Transfer: " amount
    if [ -z "$key_name" ]; then
        # shellcheck disable=SC2162
        read -p "To Key (recipient): " key_to
    else
        key_to="$key_name"
    fi
    comx balance transfer "$key_from" "$amount" "$key_to"
    echo "Transfer of $amount from $key_from to $key_to initiated."
}

# Function to unstake balance from a module
unstake_and_transfer_balance() {
    local key_from="${1:-}"
    local key_to="${2:-}"
    local key_to_transfer="${3:-}"
    local subnet="${4:-}"
    local amount="${5:-}"

    if [ -z "$key_from" ] || [ -z "$key_to" ] || [ -z "$key_to_transfer" ] || [ -z "$subnet" ] || [ -z "$amount" ]; then
        echo "Initiating Balance Unstake"
        # shellcheck disable=SC2162
        read -p "Unstake from: " key_from
        # shellcheck disable=SC2162
        read -p "Unstake to: " key_to
        # shellcheck disable=SC2162
        read -p "Transfer to: " key_to_transfer
        # shellcheck disable=SC2162
        read -p "Amount to unstake: " amount
    fi

    amount_minus_half=$(echo "$amount - 0.5" | awk '{print $1 - 0.5}')
    comx balance unstake "$key_from" "$amount" "$key_to"
    echo "$amount COM unstaked from $key_from to $key_to"

    echo "Initiating Balance Transfer"
    comx balance transfer "$key_to" "$amount_minus_half" "$key_to_transfer"
    echo "Transfer of $amount_minus_half from $key_to to $key_to_transfer initiated."
}

# Function to unstake and transfer balance of all modules
unstake_and_transfer_balance_all() {
  echo "Unstaking and transferring balance of all modules..."

  # Get the module names of all modules in the .commune/key directory
  modulenames=$(find $HOME/.commune/key -type f -name "*_*" -exec basename {} \; | sed 's/\.[^.]*$//' | tr '\n' ' ')

  # Store the module names in an array
  IFS=' ' read -r -a modulenames_array <<< "$modulenames"

  unstake_and_transfer_balance_multiple "${modulenames_array[@]}"
}

# Function to unstake and transfer balance of all modules
unstake_and_transfer_balance_name() {

  declare -a module_names=()

  echo "Enter module names ('.' to stop entering module names):"
  while true; do
      read -p "Module name: " module_name
      if [[ $module_name == "." ]]; then
          break
      fi
      module_names+=("$module_name")
  done

  # Get the module names of all modules in the .commune/key directory that match the provided module names
  modulenames=$(find $HOME/.commune/key -type f -name "*_*" -print0 | 
    xargs -0 basename -a | 
    sed 's/\.[^.]*$//' | 
    grep -E "$(IFS="|"; echo "${module_names[*]}")" | 
    tr '\n' ' ')  # Store the module names in an array
  IFS=' ' read -r -a modulenames_array <<< "$modulenames"

  unstake_and_transfer_balance_multiple "${modulenames_array[@]}"
}

# Function to unstake and transfer balance of multiple modules
unstake_and_transfer_balance_multiple() {
    declare -a module_names=()

    # Check if any module names are passed as arguments
    if [[ $# -gt 0 ]]; then
        module_names=("$@")
    else
        echo "Enter module names ('.' to stop entering module names):"
        while true; do
            read -p "Module name: " module_name
            if [[ $module_name == "." ]]; then
                break
            fi
            module_names+=("$module_name")
        done
    fi

    # Ask the user for the amount
    # shellcheck disable=SC2162
    read -p "Amount to unstake from each miner: " amount

    # Ask the user for the key to transfer the balance to
    # shellcheck disable=SC2162
    read -p "Key to transfer balance to: " key_to_transfer

    # Now the module_names array contains the names of the modules entered by the user
    echo "Module names entered: ${module_names[@]}"

    # Now the amounts array contains the amounts entered by the user
    echo "Amount to unstake and transfer: $amount"

    # You can now use the module_names and amounts arrays to perform the unstake and transfer balance operations for each module
    for module_name in "${module_names[@]}"; do
        echo "Processing module: $module_name"
        unstake_and_transfer_balance "$module_name" "$module_name" "$key_to_transfer" "$subnet" "$amount"
    done

    # Print the total amount of balance transferred - amount * number of modules
    echo "Successfully transferred: $(echo "$amount * ${#module_names[@]}" | bc -l) to $key_to_transfer"
}

# Function to transfer and stake balance of multiple modules from one key
transfer_and_stake_multiple() {
    declare -a module_names=()

    # Ask the user for the amount
    # shellcheck disable=SC2162
    read -p "Amount to stake to each miner: " amount

    echo "Enter module names ('.' to stop entering module names):"
    while true; do
        read -p "Module name: " module_name
        if [[ $module_name == "." ]]; then
            break
        fi
        module_names+=("$module_name")
    done


    # Ask the user for the key to transfer the balance to
    # shellcheck disable=SC2162
    read -p "Key to transfer balance from: " key_from


    # transfer balance and stake to each miner
    for i in "${!module_names[@]}"; do
        key_to="${module_names[i]}"
    echo "Initiating Balance Transfer"
    comx balance transfer "$key_from" "$amount" "$key_to"
    echo "Transfer of $amount from $key_from to $key_to completed."
    amount_minus_half=$(echo "$amount - 0.5" | awk '{print $1 - 0.5}')
    comx balance stake "$key_to" "$amount_minus_half" "$key_to"
    echo "$amount_minus_half COM staked from $key_to to $key_to"
        
    done
}

# Function to serve a miner
serve_miner() {
    local passed_module_path=$1
    echo "Serving Miner"
    
    # Move to the root directory if we're in scripts
    if [[ "$PWD" == */scripts ]]; then
        cd ..
    fi
    
    # Ensure we're in a virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "Activating virtual environment..."
        source .venv/bin/activate
    fi
    
    # Use environment variables if they exist, otherwise use passed parameters or ask for input
    local key_name=${MODULE_KEYNAME:-$passed_module_path}
    local port=${MODULE_PORT:-10001}  # Default to 10001 if not set
    
    if [ -z "$key_name" ]; then
        echo "Enter the miner name (e.g., Namespace.Miner_0)"
        read -p "Miner name: " key_name
        if [ -z "$key_name" ]; then
            echo "Error: Must provide a valid miner name in format Namespace.Miner_0"
            exit 1
        fi
    fi

    # Extract namespace and class name
    local namespace="${key_name%%.*}"
    local classname="${key_name#*.}"
    
    echo "Debug info:"
    echo "key_name: $key_name"
    echo "namespace: $namespace"
    echo "classname: $classname"
    
    # Clean up any existing pm2 process with this name
    echo "Cleaning up any existing process named '$key_name'..."
    pm2 delete "$key_name" 2>/dev/null || true
    sleep 1  # Give pm2 a moment to clean up
    
    echo "Starting miner process..."
    
    # Start the miner with pm2, always use 0.0.0.0 for serving
    # The module path should point to the specific class
    local module_path="synthia.miner.${namespace}.${classname}"
    
    echo "module_path: $module_path"
    echo "key: $key_name"
    
    pm2 start --name "$key_name" \
        --interpreter python3 \
        $(which comx) -- \
        module \
        serve \
        --ip "0.0.0.0" \
        --port "$port" \
        --subnets-whitelist 3 \
        "$module_path" \
        "$key_name"
        
    echo "Miner started. Checking status..."
    sleep 2  # Give pm2 a moment to start the process
    pm2 status
    echo ""
    echo "Miner served. View logs with: pm2 logs $key_name"
    
    # Return status for the calling function
    return 0
}

# Function to deploy a miner
deploy_miner() {
    echo "Deploying Miner"
    register_miner
    serve_miner "$key_name"
}

# Function to serve a validator
serve_validator() {
    echo "Serving Validator"
    # Move to the root directory if we're in scripts
    if [[ "$PWD" == */scripts ]]; then
        cd ..
    fi
    
    # Ensure we're in a virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "Activating virtual environment..."
        source .venv/bin/activate
    fi
    
    # Start the validator with pm2, passing all required arguments
    pm2 start --name "$module_path" \
        --interpreter python3 \
        -f ./src/synthia/cli.py -- \
        --key_name "$key_name" \
        --host "$host" \
        --port "$port" \
        validator "$filename"
        
    echo "Validator served."
    echo "Use 'pm2 logs' to view validator output"
}

# Function to register a miner
register_miner() {
    echo "Registering Miner"
    
    # Extract the namespace part (before the dot) and create the miner file if it doesn't exist
    local namespace="${key_name%%.*}"
    local classname="${key_name#*.}"
    local miner_file="/workspace/synthia/src/synthia/miner/${namespace}.py"
    local init_file="/workspace/synthia/src/synthia/miner/__init__.py"
    
    if [ ! -f "$miner_file" ]; then
        echo "Creating new miner file: $miner_file"
        cp "/workspace/synthia/src/synthia/miner/template_miner.py" "$miner_file"
        
        # Add import to __init__.py if not already there
        if ! grep -q "from . import $namespace" "$init_file"; then
            # Create or append to __init__.py
            if [ ! -f "$init_file" ]; then
                echo "from . import $namespace" > "$init_file"
                echo "" >> "$init_file"
                echo "__all__ = ['$namespace']" >> "$init_file"
            else
                # Add the import at the top of the file
                sed -i "1i from . import $namespace" "$init_file"
                # Update __all__ list
                if grep -q "__all__" "$init_file"; then
                    # Add to existing __all__ list
                    sed -i "s/__all__ = \[/__all__ = \['$namespace', /" "$init_file"
                else
                    # Create new __all__ list
                    echo "" >> "$init_file"
                    echo "__all__ = ['$namespace']" >> "$init_file"
                fi
            fi
        fi
    fi

    # The module path should point to the specific class
    local module_path="synthia.miner.${namespace}.${classname}"
    
    # First register the miner
    echo "Registering miner with network..."
    comx module register --ip "$MODULE_REGISTRATION_IP" --port "$port" "$module_path" "$key_name" $netuid
    
    # Check current balance
    echo "Checking current balance..."
    local free_balance
    free_balance=$(comx balance free-balance "$key_name" 2>/dev/null | grep -oP '[\d.]+(?= COMAI)')
    local max_stake
    max_stake=$(echo "$free_balance - 1" | bc -l)
    echo "Available balance: $free_balance COMAI (maximum stakeable amount: $max_stake COMAI)"
    
    # Ask if user wants to stake
    read -p "Would you like to stake tokens? [y/N] " stake_response
    if [[ "$stake_response" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter amount to stake (max $max_stake COMAI): " stake_amount
            if [[ "$stake_amount" =~ ^[0-9]+\.?[0-9]*$ ]] && \
               [ "$(echo "$stake_amount <= $max_stake" | bc -l)" -eq 1 ] && \
               [ "$(echo "$stake_amount > 0" | bc -l)" -eq 1 ]; then
                echo "Staking $stake_amount COMAI to miner..."
                comx balance stake "$key_name" "$stake_amount" "$key_name"
                break
            else
                echo "Invalid amount. Please enter a number between 0 and $max_stake"
            fi
        done
    fi
    
    echo "Miner registered and staked."
}

# Function to register a validator
register_validator() {
    echo "Registering Validator"
    # Usage: comx module register [OPTIONS] NAME KEY NETUID
    comx module register --ip "$MODULE_REGISTRATION_IP" --port "$port" "$module_path" "$key_name" $netuid
    if [ -n "$metadata" ]; then
        comx module update "$module_path" "$key_name" --metadata "$metadata"
    fi
    echo "Validator registered."
}

# Function to update a module
update_module() {
    echo "Updating Module"
    # Usage: comx module update [OPTIONS] KEY NETUID
    local options=""
    [ -n "$host" ] && options="$options --ip $host"
    [ -n "$port" ] && options="$options --port $port"
    [ -n "$module_path" ] && options="$options --name $module_path"
    
    # Execute update command with built options
    # shellcheck disable=SC2086
    comx module update $options "$key_name" $netuid
    echo "Module updated."
}

# Function to deploy a validator
deploy_validator() {
    echo "Serving Validator"
    serve_validator
    echo "Registering Validator"
    register_validator
    echo "Validator deployed."
}

# Helper Functions
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        echo "Invalid IP address format. Using default: 0.0.0.0"
        return 1
    fi
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        echo "Invalid port number. Using default: 10001"
        return 1
    fi
}

validate_number() {
    local num=$1
    local min=$2
    local max=$3
    if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -ge "$min" ] && [ "$num" -le "$max" ]; then
        return 0
    else
        return 1
    fi
}

show_help() {
    cat << EOF
Synthia Deployment Script
Usage: ./launch.sh [OPTIONS]

Options:
    --setup     Run initial setup
    --help      Show this help message

Main Operations:
    1. Deploy Validator    - Deploy and register a validator node
    2. Deploy Miner       - Deploy and register a miner node
    3. Deploy Both        - Deploy both validator and miner
    4-7. Individual Operations:
        - Register/Serve Validator
        - Register/Serve Miner
    8. Update Module      - Update existing module settings
    9-14. Balance Operations:
        - Transfer balance
        - Unstake and transfer operations
    15. Key Management    - Create new keys

Examples:
    ./launch.sh --setup   # Run initial setup
    ./launch.sh          # Show main menu
EOF
}

print_menu() {
    clear
    echo "=== Synthia Deployment Menu ==="
    echo ""
    echo "Deployment Operations:"
    echo "  1. Deploy Validator - serve and launch"
    echo "  2. Deploy Miner - serve and launch"
    echo "  3. Deploy Both - serve and launch validator and miner"
    echo ""
    echo "Individual Operations:"
    echo "  4. Register Validator"
    echo "  5. Register Miner"
    echo "  6. Serve Validator"
    echo "  7. Serve Miner"
    echo "  8. Update Module - either validator or miner"
    echo ""
    echo "Balance Operations:"
    echo "  9.  Transfer Balance"
    echo "  10. Unstake and Transfer Balance - 1 miner"
    echo "  11. Unstake and Transfer Balance - specific miners"
    echo "  12. Unstake and Transfer Balance - ALL miners"
    echo "  13. Unstake and Transfer Balance - ALL miners by name"
    echo "  14. Transfer and Stake - multiple miners"
    echo ""
    echo "Key Management:"
    echo "  15. Create Key"
    echo ""
    echo "  0. Exit"
    echo ""
}

if [ "$1" = "--setup" ]; then
    create_setup
fi

if [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

while true; do
    print_menu
    # shellcheck disable=SC2162
    read -p "Choose an action " choice
    echo ""

    case "$choice" in
    1)
        echo "Validator Configuration"
        is_validator=true
        needs_stake=true
        is_update=true
        configure_launch
        deploy_validator
        ;;
    2)
        echo "Miner Configuration"
        is_miner=true
        needs_stake=true
        is_update=true
        configure_launch
        deploy_miner
        ;;
    3)
        echo "Validator Configuration"
        is_validator=true
        needs_stake=true
        is_update=true
        configure_launch
        deploy_validator
        echo "Miner Configuration"
        is_validator=false
        is_miner=true
        needs_stake=true
        is_update=true
        configure_launch
        deploy_miner
        ;;
    4)
        echo "Validator Configuration"
        is_validator=true
        needs_stake=true
        is_update=true
        configure_launch
        register_validator
        ;;
    5)
        echo "Miner Configuration"
        is_miner=true
        needs_stake=true
        is_update=true
        configure_launch
        register_miner
        ;;
    6)
        echo "Validator Configuration"
        is_validator=true
        configure_launch
        serve_validator
        ;;
    7)
        echo "Serving Miner"
        if serve_miner; then
            echo ""
            read -p "Would you like to (q)uit or (c)ontinue to menu? [q/c]: " choice
            case "$choice" in
                q|Q) exit 0 ;;
                *) echo "" ;;  # Continue to menu for any other input
            esac
        else
            echo "Miner failed to start. Please check logs and try again."
            read -p "Press enter to continue..."
        fi
        ;;
    8)
        echo "Module Configuration"
        is_update=true
        configure_launch
        update_module
        ;;
    9)
        transfer_balance
        ;;
    10)
        unstake_and_transfer_balance
        ;;
    11)
        unstake_and_transfer_balance_multiple
        ;;
    12)
        unstake_and_transfer_balance_all
        ;;
    13)
        unstake_and_transfer_balance_name
        ;;
    14)
        transfer_and_stake_multiple
        ;;
    15)
        create_key
        ;;
    0)
        exit 0
        ;;
    *)
        echo "Invalid choice"
        ;;
    esac

    echo "Action complete."
done