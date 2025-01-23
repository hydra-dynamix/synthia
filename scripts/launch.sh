#!/bin/bash

# MIT License - Copyright (c) 2023 Bakobiibizo (https://github.com/bakobiibizo)

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

# Store miner ports file location
MINER_PORTS_FILE="$HOME/.commune/miner_ports.txt"

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
    # Store port range configuration
    PORT_CONFIG_FILE="$HOME/.commune/port_config.txt"

    # Get configured port range
    read -r start_port end_port <<< "$(get_port_range)"
    
    # Check if port is already assigned to this miner
    local saved_port=""
    if [ -f "$MINER_PORTS_FILE" ]; then
        saved_port=$(grep "^$key_name:" "$MINER_PORTS_FILE" | cut -d':' -f2)
    fi

    if [ -n "$saved_port" ]; then
        # Verify saved port is still in valid range
        if [ "$saved_port" -ge "$start_port" ] && [ "$saved_port" -le "$end_port" ]; then
            echo "Found previously registered port for $key_name: $saved_port"
            port=$saved_port
        else
            echo "Warning: Previously saved port $saved_port is outside configured range ($start_port-$end_port)"
            saved_port=""
        fi
    fi

    if [ -z "$saved_port" ]; then
        while true; do
            # Find the next available port in the configured range
            local suggested_port=$start_port
            if [ -f "$MINER_PORTS_FILE" ]; then
                while [ "$suggested_port" -le "$end_port" ] && grep -q ":$suggested_port$" "$MINER_PORTS_FILE"; do
                    suggested_port=$((suggested_port + 1))
                done
            fi
            
            if [ "$suggested_port" -gt "$end_port" ]; then
                echo "No available ports in range $start_port-$end_port"
                echo "Would you like to:"
                echo "1. Configure a different port range"
                echo "2. Enter a specific port"
                echo "3. Exit"
                read -p "Choose an option (1-3): " port_option
                case "$port_option" in
                    1)
                        configure_port_range
                        read -r start_port end_port <<< "$(get_port_range)"
                        continue
                        ;;
                    2)
                        suggested_port=""
                        ;;
                    *)
                        echo "Exiting..."
                        exit 1
                        ;;
                esac
            fi
            
            if [ -n "$suggested_port" ]; then
                echo "Suggested available port: $suggested_port (from range $start_port-$end_port)"
            else
                echo "Enter a port number between $start_port and $end_port"
            fi
            
            # shellcheck disable=SC2162
            read -p "Module port (press Enter to use suggested port): " port
            [ -z "$port" ] && port=$suggested_port
            
            if ! validate_port "$port"; then
                continue
            fi
            
            # Verify port is in configured range
            if [ "$port" -lt "$start_port" ] || [ "$port" -gt "$end_port" ]; then
                echo "Port must be between $start_port and $end_port"
                continue
            fi
            
            # Check if port is already in use by another miner
            if [ -f "$MINER_PORTS_FILE" ] && grep -q ":$port$" "$MINER_PORTS_FILE"; then
                echo "Port $port is already assigned to another miner"
                continue
            fi
            break
        done
        
        # Save the port assignment
        mkdir -p "$(dirname "$MINER_PORTS_FILE")"
        echo "$key_name:$port" >> "$MINER_PORTS_FILE"
    fi

    # Enter the netuid of the module with validation
    while true; do
        # shellcheck disable=SC2162
        read -p "Deploying to subnet (default 3): " netuid
        [ -z "$netuid" ] && netuid=3
        validate_number "$netuid" 0 100 && break
        echo "Please enter a valid subnet number (0-100)"
    done

    key_name=$key_name

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
        echo "Add metadata (y/n): " choose_metadata
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
    echo "Module names entered: ${module_names[*]@Q}"

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
    local test_mode=false
    
    # Parse arguments
    while (( "$#" )); do
        case "$1" in
            --test-mode)
                test_mode=true
                shift
                ;;
            *)
                if [ -z "$passed_module_path" ]; then
                    passed_module_path=$1
                fi
                shift
                ;;
        esac
    done

    echo "Serving Miner"
    
    # Move to the root directory if we're in scripts
    if [[ $PWD == */scripts ]]; then
        cd ..
    fi
    
    # Ensure we're in a virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "Activating virtual environment..."
        source .venv/bin/activate
    fi
    
    # Use environment variables if they exist, otherwise use passed parameters or ask for input
    local key_name=${MODULE_KEYNAME:-$passed_module_path}
    
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

    # Check if the miner module exists
    local miner_path="src/synthia/miner/${namespace}.py"
    if [ ! -f "$miner_path" ]; then
        echo "Miner module $namespace not found. Creating it from template..."
        # Create the miner module from template
        cat > "$miner_path" << EOL
from .template_miner import BaseMiner, miner_map

class ${classname}(BaseMiner):
    def __init__(self) -> None:
        super().__init__()

# Add the miner to the miner map
miner_map["${classname}"] = ${classname}
EOL
        echo "Created new miner module at $miner_path"
    fi

    # Look up the port from saved configuration
    local port=""
    # Create the directory if it doesn't exist
    mkdir -p "$(dirname "$MINER_PORTS_FILE")"
    if [ -f "$MINER_PORTS_FILE" ]; then
        port=$(grep "^$key_name:" "$MINER_PORTS_FILE" | cut -d':' -f2)
    fi

    if [ -z "$port" ]; then
        echo "WARNING: No saved port found for miner $key_name"
        echo "The port must match the one used during registration"
        read -p "Enter the port used during registration: " port
        if ! validate_port "$port"; then
            echo "Invalid port number"
            exit 1
        fi
        # Save the port for future use
        mkdir -p "$(dirname "$MINER_PORTS_FILE")"
        echo "$key_name:$port" >> "$MINER_PORTS_FILE"
    else
        echo "Using saved port: $port"
    fi
    
    echo "Debug info:"
    echo "key_name: $key_name"
    echo "namespace: $namespace"
    echo "classname: $classname"
    echo "port: $port"
    
    # Clean up any existing pm2 process with this name
    echo "Cleaning up any existing process named '$key_name'..."
    pm2 delete "$key_name" 2>/dev/null || true
    sleep 1  # Give pm2 a moment to clean up
    
    echo "Starting miner process..."
    
    if [ "$test_mode" = true ]; then
        echo "Running in test mode with higher rate limits"
        export CONFIG_IP_LIMITER_BUCKET_SIZE=1000  # Allow more requests in the bucket
        export CONFIG_IP_LIMITER_REFILL_RATE=100   # Refill faster
    fi

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
    
    # Check for required environment variables
    if [ -z "$ANTHROPIC_api_key" ]; then
        echo "Error: ANTHROPIC_api_key environment variable is not set"
        echo "Please set it in your env/config.env file or export it directly"
        return 1
    fi
    
    # Move to the root directory if we're in scripts
    if [[ "$PWD" == */scripts ]]; then
        cd ..
    fi
    
    # Ensure we're in a virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "Activating virtual environment..."
        source .venv/bin/activate
    fi
    
    # Extract the namespace and class name
    local namespace="${key_name%%.*}"
    local classname="${key_name#*.}"
    local module_path="synthia.validator.${namespace}.${classname}"
    
    # Clean up any existing PM2 processes with this name
    echo "Cleaning up any existing validator processes..."
    pm2 delete "$module_path" 2>/dev/null || true
    
    # Start the validator with pm2, passing all required arguments
    echo "Starting validator..."
    if pm2 start --name "$module_path" \
        --interpreter python3 \
        -f ./src/synthia/cli.py -- \
        --key_name "$key_name" \
        --host "$host" \
        --port "$port" \
        validator "$filename"; then
        
        echo "Validator started successfully."
        echo "Use 'pm2 logs' to view validator output"
        echo "Use 'pm2 stop $module_path' to stop the validator"
        return 0
    else
        echo "Failed to start validator. Check the logs for more information."
        return 1
    fi
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
    
    # Extract the namespace part (before the dot) and create proper module path
    local namespace="${key_name%%.*}"
    local classname="${key_name#*.}"
    local module_path="synthia.validator.${namespace}.${classname}"
    
    # First register the validator
    echo "Registering validator with network..."
    comx module register --ip "$MODULE_REGISTRATION_IP" --port "$port" "$module_path" "$key_name" $netuid
    
    if [ -n "$metadata" ]; then
        comx module update "$module_path" "$key_name" --metadata "$metadata"
    fi
    
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
                echo "Staking $stake_amount COMAI to validator..."
                comx balance stake "$key_name" "$stake_amount" "$key_name"
                break
            else
                echo "Invalid amount. Please enter a number between 0 and $max_stake"
            fi
        done
    fi
    
    echo "Validator registered and staked."
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

# Function to get port range
get_port_range() {
    local start_port=10001
    local end_port=10200

    if [ -f "$HOME/.commune/port_config.txt" ]; then
        local temp_start
        local temp_end
        temp_start=$(grep "^START_PORT=" "$HOME/.commune/port_config.txt" | cut -d'=' -f2)
        temp_end=$(grep "^END_PORT=" "$HOME/.commune/port_config.txt" | cut -d'=' -f2)
        if [ -n "$temp_start" ] && [ -n "$temp_end" ]; then
            start_port=$temp_start
            end_port=$temp_end
        fi
    fi

    printf "%d %d" "$start_port" "$end_port"
}

# Function to set port range
configure_port_range() {
    echo "Configure port range for miners"
    echo "These ports must be open and accessible from the network"
    
    local current_range
    current_range=$(get_port_range)
    local current_start
    local current_end
    read -r current_start current_end <<< "$current_range"
    
    while true; do
        read -p "Enter start port (current: $current_start): " start_port
        if [ -z "$start_port" ]; then
            start_port=$current_start
            break
        fi
        if validate_port "$start_port"; then
            break
        fi
    done

    while true; do
        read -p "Enter end port (current: $current_end): " end_port
        if [ -z "$end_port" ]; then
            end_port=$current_end
            break
        fi
        if validate_port "$end_port" && [ "$end_port" -gt "$start_port" ]; then
            break
        fi
        echo "End port must be greater than start port ($start_port)"
    done

    # Create the .commune directory if it doesn't exist
    if [ ! -d "$HOME/.commune" ]; then
        mkdir -p "$HOME/.commune"
    fi

    # Write the configuration using a temporary file for atomicity
    local temp_file
    temp_file=$(mktemp)
    {
        echo "START_PORT=$start_port"
        echo "END_PORT=$end_port"
    } > "$temp_file"
    mv "$temp_file" "$HOME/.commune/port_config.txt"
    
    echo "Port range configured: $start_port-$end_port"
}

# Function to serve a test miner
serve_test_miner() {
    echo "Starting test miner with higher rate limits..."
    
    # Move to the root directory if we're in scripts
    if [[ $PWD == */scripts ]]; then
        cd ..
    fi

    # Prompt for miner name
    echo "Enter the name of an existing miner (e.g., Rabbit.Miner_0)"
    read -p "Miner name: " key_name

    # Check if miner ports file exists
    MINER_PORTS_FILE="$HOME/.commune/miner_ports.txt"
    if [ ! -f "$MINER_PORTS_FILE" ]; then
        echo " No miner ports file found at $MINER_PORTS_FILE"
        return 1
    fi
    
    # Look up the port from saved configuration
    local port=$(grep "^$key_name:" "$MINER_PORTS_FILE" | cut -d':' -f2)
    
    if [ -z "$port" ]; then
        echo " No port found for miner $key_name"
        echo "Make sure the miner is registered and running"
        return 1
    fi

    echo "Found port $port for miner $key_name"
    
    # First stop any existing instance
    pm2 delete "$key_name" 2>/dev/null || true
    
    # Create a shell script to run the miner with environment variables
    local run_script="/tmp/run_miner_$key_name.sh"
    cat > "$run_script" << EOF
#!/bin/bash
source .venv/bin/activate

# Set higher IP rate limits
export CONFIG_IP_LIMITER_BUCKET_SIZE=1000
export CONFIG_IP_LIMITER_REFILL_RATE=100

# Set higher stake rate limits
export CONFIG_STAKE_LIMITER_EPOCH=10
export CONFIG_STAKE_LIMITER_CACHE_AGE=600
export CONFIG_STAKE_LIMITER_TOKEN_RATIO=100

exec python3 -m synthia.miner.cli "$key_name" --port "$port" --ip "0.0.0.0"
EOF
    chmod +x "$run_script"
    
    echo "Starting miner with rate limits:"
    echo "  IP Limiter: bucket_size=1000, refill_rate=100"
    echo "  Stake Limiter: epoch=10, token_ratio=100"
    
    # Start the miner using the shell script
    pm2 start "$run_script" --name "$key_name" --update-env
    
    echo "Miner started in test mode. Press Enter to continue..."
    read
}

# Function to test a miner
test_miner() {
    local miner_name=$1
    
    if [ -z "$miner_name" ]; then
        read -p "Enter miner name (e.g., Rabbit.Miner_0): " miner_name
    fi
    
    # Check if miner ports file exists
    MINER_PORTS_FILE="$HOME/.commune/miner_ports.txt"
    if [ ! -f "$MINER_PORTS_FILE" ]; then
        echo " No miner ports file found at $MINER_PORTS_FILE"
        return 1
    fi
    
    # Look up the port from saved configuration
    local port=$(grep "^$miner_name:" "$MINER_PORTS_FILE" | cut -d':' -f2)
    
    if [ -z "$port" ]; then
        echo " No port found for miner $miner_name"
        echo "Make sure the miner is registered first"
        return 1
    fi

    echo "Testing miner $miner_name on port $port..."
    
    # Save current directory
    local current_dir="$PWD"
    
    # Move to scripts directory if we're not already there
    if [[ $PWD != */scripts ]]; then
        cd scripts || return 1
    fi
    
    # Run the test script and capture its output
    echo "Running test..."
    echo "----------------------------------------"
    if python3 test_miner.py "$port" "Test request to verify miner functionality" "$miner_name"; then
        echo "----------------------------------------"
        echo "Test completed successfully!"
    else
        echo "----------------------------------------"
        echo "Test failed!"
    fi
    
    # Return to original directory
    cd "$current_dir" || return 1

    # Ask user what to do next
    while true; do
        echo -e "\nWhat would you like to do?"
        echo "1) Return to main menu"
        echo "2) Run test again"
        echo "3) Exit"
        read -p "Choose an option (1-3): " choice
        
        case $choice in
            1) return 0 ;;
            2) test_miner "$miner_name" ;;
            3) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
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
Usage: ./launch.sh [OPTIONS] [COMMAND] [PARAMETERS]

Commands:
  serve_miner <name> [--test-mode]     Start a miner process
    Parameters:
      name                             Miner name in format Namespace.Miner_0
      --test-mode                      Use higher rate limits for testing

  serve_validator <name>               Start a validator process
    Parameters:
      name                             Validator name in format Namespace.Validator_0

  create_key <name>                    Create a new key
    Parameters:
      name                             Name for the new key

  transfer_balance                     Transfer balance between keys
    Parameters:
      source_key                       Source key name
      target_key                       Target key name
      amount                           Amount to transfer

  register_miner <name>                Register a miner
    Parameters:
      name                             Miner name in format Namespace.Miner_0
      --port <port>                    Optional: Specify port (default: auto-assigned)
      --provider <provider>            Optional: Specify provider (anthropic/openrouter)

  register_validator <name>            Register a validator
    Parameters:
      name                             Validator name in format Namespace.Validator_0
      --port <port>                    Optional: Specify port (default: auto-assigned)

  update_module <name>                 Update a module
    Parameters:
      name                             Module name to update

  deploy_miner <name>                  Deploy a miner
    Parameters:
      name                             Miner name to deploy

  deploy_validator <name>              Deploy a validator
    Parameters:
      name                             Validator name to deploy

  configure_port_range                 Configure the port range for modules
    Parameters:
      start_port                       Starting port number
      end_port                         Ending port number

  test_miner <name>                    Test a miner's functionality
    Parameters:
      name                             Miner name to test
      --prompt <prompt>                Optional: Test prompt

Global Options:
  --help                              Show this help message
  --setup                             Run initial setup

Environment Variables:
  MODULE_KEYNAME                      Pre-set module name (optional)
  CONFIG_IP_LIMITER_BUCKET_SIZE      Request bucket size for rate limiting
  CONFIG_IP_LIMITER_REFILL_RATE      Rate limit refill rate

Examples:
  ./launch.sh serve_miner OpenAI.Miner_0 --test-mode    # Start a miner with test mode
  ./launch.sh register_miner Anthropic.Miner_0 --port 8080 --provider anthropic
  ./launch.sh serve_validator Text.Validator_0          # Start a validator
  ./launch.sh                                          # Show interactive menu

Port Management:
  - Ports are stored in ~/.commune/miner_ports.txt
  - Each module needs a consistent port across registrations and serving
  - Default port range: 8000-9000

Notes:
  - Key names should be unique across your deployment
  - Provider selection affects which API will be used
  - Test mode increases rate limits for development
  - Always ensure proper configuration in env/config.env
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
    echo ""
    echo "Module Operations:"
    echo "  8. Update Module"
    echo "  9. Configure Port Range"
    echo ""
    echo "Balance Operations:"
    echo "  10. Transfer Balance"
    echo "  11. Unstake and Transfer Balance"
    echo "  12. Unstake and Transfer Balance - Multiple"
    echo "  13. Unstake and Transfer Balance - All"
    echo "  14. Unstake and Transfer Balance - By Name"
    echo "  15. Transfer and Stake Multiple"
    echo ""
    echo "Testing & Management:"
    echo "  16. Create Key"
    echo "  17. Test Miner"
    echo "  18. Exit"
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
    read -p "Choose an option (1-18): " choice
    
    case $choice in
        1) deploy_validator ;;
        2) deploy_miner ;;
        3)
            deploy_validator
            deploy_miner
            ;;
        4) register_validator ;;
        5) register_miner ;;
        6) serve_validator ;;
        7) if serve_miner; then
                echo -e "\nPress Enter to continue..."
                read
           fi ;;
        8) update_module ;;
        9) configure_port_range ;;
        10) transfer_balance ;;
        11) unstake_and_transfer_balance ;;
        12) unstake_and_transfer_balance_multiple ;;
        13) unstake_and_transfer_balance_all ;;
        14) unstake_and_transfer_balance_name ;;
        15) transfer_and_stake_multiple ;;
        16) create_key ;;
        17) if test_miner; then
                echo -e "\nPress Enter to continue..."
                read
            fi
            ;;
        18) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done