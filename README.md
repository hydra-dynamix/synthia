# Synthia

Welcome to the Synthia subnet, a bleeding-edge initiative to accelerate the open-source AI space. Our mission is to harness the power of Commune's decentralized incentive markets to produce a continuous stream of synthetic training data with verified quality at scale.

## Table of Contents

- [Synthia](#synthia)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Motivation](#motivation)
  - [Resources](#resources)
  - [Installation](#installation)
    - [Setup your environment](#setup-your-environment)
      - [With Docker](#with-docker)
        - [Operating with docker](#operating-with-docker)
      - [Manually, on Ubuntu 22.04](#manually-on-ubuntu-2204)
      - [With Nix](#with-nix)
  - [Launcher Script](#launcher-script)
    - [Using the Launcher](#using-the-launcher)
    - [Running A Miner](#running-a-miner)
      - [Miner Configuration](#miner-configuration)
      - [Port Configuration](#port-configuration)
    - [Running A Validator](#running-a-validator)
  - [Hardware Requirements](#hardware-requirements)
    - [Minimum Requirements](#minimum-requirements)
    - [Recommended Requirements](#recommended-requirements)

## Overview

Synthia is utilizing the state-of-the-art Anthropic Claude3 API to generate open-ended high-quality and diverse synthetic in-depth explanations of subjects picked from the Opus latent space based on varying esotericity, with varying target-audience, level of detail and abstraction at scale.

While any model or API can theoretically mine in the subnet, the validation is designed to target Claude3-level quality, due to its substantially superior ability to generate the desired synthetic data. Hence, we advise mining with the Claude3 API, although support for OpenAI's API is available.

## Motivation

In the rapidly evolving world of artificial intelligence, synthetic data has emerged as a crucial component in the training of advanced models. By utilizing the state-of-the-art Anthropic Claude3 API, we can generate open-ended subject-unconstrained high-quality and diverse synthetic in-depth explanations.

Major AI labs have already recognized the potential of synthetic data and are actively utilizing it to enhance their models. However, access to such data remains limited for the broader open-source community. The Synthia subnet aims to change that.

By harnessing the power of Commune's decentralized crypto-economic incentives, we aim to create the largest reliably high-quality synthetic intelligence dataset in the world that will serve as a catalyst for innovation in the Open-Source AI space.

Join us on this important journey as we distill the Closed-Source intelligence right into the hands of the Open-Source Community!

## Resources

- You can check the HuggingFace leaderboard [here](https://huggingface.co/spaces/agicommies/synthia_subnet_leaderboard)!
- You can see the real-time dataset produced by Synthia [here](https://huggingface.co/datasets/agicommies/synthia)!

## Installation

Make sure you are on the latest CommuneX version.

```sh
pip install communex --upgrade
```

### Setup your environment

#### With Docker

- [Install Docker](https://docs.docker.com/get-docker/)
- Run `docker pull ghcr.io/agicommies/synthia:9d23f1f`
- Run `docker run -v ~/.commune:/root/.commune -it [-p <port>:<port>] ghcr.io/agicommies/synthia:9d23f1f`
- Run `poetry shell` to enter the enviroment

##### Operating with docker

- You can quit docker with ctrl+d
- You can dettach from your session with ctrl+p followed by ctrl+q
- You can attach back to your session by running `docker attach <id>`
- You can list the ids of your containers with `docker ps`
- Note that you should pass the ports you're going to use to the container (with `-p <port>:<port>`) to bind them to your host machine.
- You can pass enviroments variables to docker with `-e <VARIABLE>=<value>`.
  e.g `docker run -e ANTHROPIC_API_KEY=<your-anthropic-api-key> -v ~/.commune:/root/.commune -it ghcr.io/agicommies/synthia:9d23f1f`

#### Manually, on Ubuntu 22.04

- Install Python 3
  - `sudo apt install python3`
- [Install Poetry](https://python-poetry.org/docs/)
- Install the Python dependencies with `poetry install`
- **! IMPORTANT** Enter the Python environment with `poetry shell`

#### With Nix

- Install Nix with [install.determinate.systems]
- You can enter the nix shell environment with with `nix develop` or setup
  [direnv](https://direnv.net/) to automatically load the environment when you
  enter the directory.
- Install the Python dependencies with `poetry install`
- Get into the Python environment:
  - If you are using `direnv`, just re-entering the directory will do the trick.
    - Tip: you can force-reload with `direnv reload`
  - If not, you can run `poetry shell` to enter the Python environment.

[install.determinate.systems]: https://install.determinate.systems/

## Launcher Script

The `launch.sh` script in the `scripts` directory provides an interactive way to configure and run your miner or validator.

### Using the Launcher

Allow commands to be executed by the script:

```sh
chmod +x scripts/launch.sh
```

Run the launcher:

```sh
bash scripts/launch.sh
```

Just follow the prompts after that.

### What it does

The launch script will prompt you step by step through the process of launching
a validator or miner or both and execute the required commands without having
to know details about the CLI.

Be aware that the launcher does execute commands that make changes on the block chain including balance transfers and module registration. Be sure you know what you'd like to do before using this tool as some actions cannot be undone. This tool is provided free of charge as is and with no warranty or guarantee. Use at your own risk.

### Running A Miner

1. Get an API key from [Anthropic](https://console.anthropic.com/).
2. Create a file named `config.env` in the `env/` folder with the following
   contents (you can also see the `env/config.env.sample` as an example):

   ```sh
   ANTHROPIC_API_KEY="<your-anthropic-api-key>"
   ```

#### Miner Configuration

The `launch.sh` script in the `scripts` directory provides an interactive way to configure and run your miner. Here are the relevant options for mining:

1. **Namespace and Naming**:

   - When prompted for module name, use the format: `Namespace.Miner_X`
   - Example: `Rabbit.Miner_0`, `Synthia.Miner_1`
   - The namespace (e.g., `Rabbit`) is your unique identifier
   - The number suffix (e.g., `_0`) distinguishes multiple miners under the same namespace
   - Each namespace can have up to 20 miners (0 - 19)

2. **Launch Script Options**:

   - Option 2: `Deploy Miner` - Complete setup of a new miner (combines registration and serving)
   - Option 5: `Register Miner` - Register a new miner on the network
   - Option 7: `Serve Miner` - Start a registered miner
   - Option 8: `Update Module` - Update an existing miner's configuration
   - Option 9: `Configure Port Range` - Set the port range for multiple miners
   - Option 15: `Create Key` - Create a new key for your miner

3. **Registration Process (Option 5)**:

   - Enter your namespace and miner name
   - Provide the IP address that other nodes will use to connect to your miner
   - Select a port from your configured range
   - Set stake amount (minimum 256 COM)
   - Set delegation fee percentage
   - The script will save your port assignment for future use

4. **Serving Process (Option 7)**:
   - Enter the same namespace and miner name used during registration
   - The script will automatically:
     - Use the saved port from registration
     - Start the miner using PM2 for process management
     - Configure the miner to accept external connections (0.0.0.0)

#### Port Configuration

When running multiple miners on one machine, each miner needs its own unique port. Configure this using Option 9 in the launch script:

1. Use option 9 in the launcher menu to configure your port range
2. Set your preferred port range (e.g., 50000-50200)
3. The script will automatically:
   - Suggest available ports from your configured range
   - Save port assignments for each miner
   - Ensure port consistency between registration and serving

When using Docker, remember to expose your port range:

```bash
docker run -v ~/.commune:/root/.commune -p 50000-50200:50000-50200 -it ghcr.io/agicommies/synthia:9d23f1f
```

**Note**:

- Make sure to **serve and register** the module using the **same key**
- Your namespace should be unique to avoid conflicts with other miners
- Keep track of your miner names if running multiple instances
- The port used for registration must match the port used for serving

### Running A Validator

1. Get an API key from [Anthropic](https://console.anthropic.com/).

2. Gen an API key for embeddings from [OpenAi](https://openai.com/product)

3. Create a file named `config.env` in the `env/` folder with the following contents (you can also see the `env/config.env.sample` as an example):

   ```sh
   ANTHROPIC_API_KEY="<your-anthropic-claude-api-key>"
   OPENROUTER_API_KEY="<your-openrouter-api-key>"
   ANTHROPIC_MODEL=claude-3-opus-20240229
   ANTHROPIC_MAX_TOKENS=1000
   ANTHROPIC_TEMPERATURE=0.5
   OPENAI_API_KEY="<your-openai-api-key>"
   ```

   Alternatively, you can set up those values as enviroment variables.

4. Register the validator

   Note that you are required to register the validator first, this is because the validator has to be on the network in order to set weights. You can do this by running the following command:

   ```sh
   comx module register <name> <your_commune_key> --netuid <synthia netuid>
   ```

   The current synthia **netuid** is **3**.

5. Serve the validator

   ```sh
   python3 -m synthia.cli <your_commune_key> [--call-timeout <seconds>] [--provider <provider_name>]
   ```

   The default value of the `--call-timeout` parameter is 65 seconds.
   You can pass --provider openrouter to run using openrouter provider

   Note: you need to keep this process alive, running in the background. Some options are [tmux](<https://www.tmux.org/](https://ioflood.com/blog/install-tmux-command-linux/)>), [pm2](https://pm2.io/docs/plus/quick-start/) or [nohup](https://en.wikipedia.org/wiki/Nohup).

## Hardware Requirements

### Minimum Requirements

- **CPU:** Quad-core Intel i3 or equivalent AMD processor, 2.5 GHz
- **RAM:** 2 GB
- **Storage:** 500mb + of free space
- **GPU:** Not needed
- **Network:** Broadband internet connection for online data syncing

### Recommended Requirements

If you want to run up to ~10+ miners / validators

- **CPU:** 4-core Intel i5 or equivalent AMD processor, 2.5 GHz-3.5 GHz
- **RAM:** 4 GB or more
- **Storage:** 128 GB SSD
- **GPU:** Not needed
- **Network:** Gigabit Ethernet or better
