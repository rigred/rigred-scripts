# Rigo's Scripts Collection
This is a curated collection of shell scripts for system diagnostics, hardware interaction, and performance tuning, primarily for Linux systems. These scripts are developed and maintained for use in projects and articles featured on my blog, [Rigo's Web](https://0xcats.net).

## Quick Start
You can download and run any script directly from this repository. Find the script you need in the Scripts Index below and use its path with curl or wget.

### Example: Running the NUMA Info Script
```sh
# Download the script using curl
curl -LO https://raw.githubusercontent.com/rigred/rigred-scripts/main/diagnostics/get_numa_info.sh

# Or with wget
wget https://raw.githubusercontent.com/rigred/rigred-scripts/main/diagnostics/get_numa_info.sh

# Make it executable
chmod +x get_numa_info.sh

# Run it
sudo ./get_numa_info.sh
```

## Folder Structure

```
The repository is organized by script category to make discovery easy and intuitive..
├── diagnostics/      # System analysis and performance diagnostics
├── hardware/         # Interacting with specific hardware (CPU, GPU)
├── networking/       # Network configuration and monitoring tools
└── utils/            # General-purpose helper scripts and utilities
```

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.

1. Fork the Project
2. Create your Feature Branch (git checkout -b feature/AmazingScript)
3. Commit your Changes (git commit -m 'Add some AmazingScript')
4. Push to the Branch (git push origin feature/AmazingScript)
5. Open a Pull Request

## License
Distributed under the MIT License. See `LICENSE` file for more information.
