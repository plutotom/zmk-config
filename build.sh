#!/bin/bash

# ZMK Build Script
# This script builds all configurations defined in build.yaml

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ZMK_APP_PATH="."
CONFIG_PATH="$(pwd)/config"
BUILD_DIR="build"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a ZMK workspace
check_zmk_workspace() {
    if [[ ! -d "$ZMK_APP_PATH" ]]; then
        print_error "ZMK app not found at $ZMK_APP_PATH"
        print_error "You need to set up a ZMK workspace first."
        echo
        print_status "To set up ZMK workspace, run these commands:"
        echo "  mkdir ~/zmk-dev"
        echo "  cd ~/zmk-dev"
        echo "  west init -m https://github.com/zmkfirmware/zmk.git --mr main"
        echo "  west update"
        echo "  west zephyr-export"
        echo
        print_status "Then copy your zmk-config to the workspace:"
        echo "  cp -r /Users/proctoi/Documents/Coding/custom-keyboard/zmk-config ~/zmk-dev/"
        echo "  cd ~/zmk-dev/zmk-config"
        echo "  ./build.sh"
        echo
        exit 1
    fi
}

# Function to parse build.yaml and extract configurations
parse_build_yaml() {
    local yaml_file="build.yaml"
    
    if [[ ! -f "$yaml_file" ]]; then
        print_error "build.yaml not found in current directory"
        exit 1
    fi
    
    # Extract board and shield combinations from the include section
    local line_num=0
    local in_include=false
    local current_board=""
    local current_shield=""
    local current_artifact=""
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Check if we're in the include section
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*board:[[:space:]]* ]]; then
            in_include=true
            current_board=$(echo "$line" | sed 's/.*board:[[:space:]]*//')
        elif [[ "$line" =~ ^[[:space:]]*shield:[[:space:]]* ]] && [[ "$in_include" == true ]]; then
            current_shield=$(echo "$line" | sed 's/.*shield:[[:space:]]*//')
        elif [[ "$line" =~ ^[[:space:]]*artifact-name:[[:space:]]* ]] && [[ "$in_include" == true ]]; then
            current_artifact=$(echo "$line" | sed 's/.*artifact-name:[[:space:]]*//')
        elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*$ ]] && [[ "$in_include" == true ]]; then
            # End of current configuration
            if [[ -n "$current_board" ]]; then
                echo "$current_board|$current_shield|$current_artifact"
            fi
            current_board=""
            current_shield=""
            current_artifact=""
        fi
    done < "$yaml_file"
    
    # Handle last configuration if no trailing empty line
    if [[ -n "$current_board" ]]; then
        echo "$current_board|$current_shield|$current_artifact"
    fi
}

# Function to build a single configuration
build_config() {
    local board="$1"
    local shield="$2"
    local artifact_name="$3"
    
    local build_name="${board}_${shield}"
    if [[ -n "$artifact_name" ]]; then
        build_name="$artifact_name"
    fi
    
    local build_path="$BUILD_DIR/$build_name"
    
    print_status "Building $board with shield $shield..."
    
    # Create build directory
    mkdir -p "$build_path"
    
    # Build command - use absolute path to ZMK app
    local build_cmd="west build -d $build_path -b $board -s $ZMK_APP_PATH"
    
    # Add shield if specified
    if [[ -n "$shield" ]]; then
        build_cmd="$build_cmd -- -DSHIELD=$shield"
    fi
    
    # Add config path
    build_cmd="$build_cmd -DZMK_CONFIG=$CONFIG_PATH"
    
    print_status "Running: $build_cmd"
    
    # Execute build
    if eval "$build_cmd"; then
        print_success "Build completed for $build_name"
        
        # Check if firmware file was created
        local firmware_file="$build_path/zephyr/zmk_${board}_${shield}.uf2"
        if [[ -f "$firmware_file" ]]; then
            print_success "Firmware created: $firmware_file"
        else
            print_warning "Firmware file not found at expected location"
            # Try to find any .uf2 file
            local found_firmware=$(find "$build_path" -name "*.uf2" -type f | head -1)
            if [[ -n "$found_firmware" ]]; then
                print_success "Found firmware: $found_firmware"
            fi
        fi
    else
        print_error "Build failed for $build_name"
        return 1
    fi
}

# Function to list all built firmwares
list_firmwares() {
    if [[ -d "$BUILD_DIR" ]]; then
        local firmwares=$(find "$BUILD_DIR" -name "*.uf2" -type f)
        if [[ -n "$firmwares" ]]; then
            print_status "Built firmwares:"
            echo "$firmwares" | while read -r firmware; do
                local size=$(du -h "$firmware" | cut -f1)
                print_success "  $firmware ($size)"
            done
        else
            print_warning "No firmware files found in build directory"
        fi
    else
        print_warning "Build directory does not exist"
    fi
}

# Function to clean build directories
clean_builds() {
    if [[ -d "$BUILD_DIR" ]]; then
        print_status "Cleaning build directories..."
        rm -rf "$BUILD_DIR"
        print_success "Build directories cleaned"
    else
        print_warning "No build directory to clean"
    fi
}

# Function to set up ZMK workspace
setup_zmk_workspace() {
    print_status "Setting up ZMK workspace..."
    
    local workspace_dir="$HOME/zmk-dev"
    
    if [[ -d "$workspace_dir" ]]; then
        print_warning "ZMK workspace already exists at $workspace_dir"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$workspace_dir"
        else
            print_status "Using existing workspace"
            return 0
        fi
    fi
    
    mkdir -p "$workspace_dir"
    cd "$workspace_dir"
    
    print_status "Initializing West workspace..."
    west init -m https://github.com/zmkfirmware/zmk.git --mr main
    
    print_status "Updating West workspace..."
    west update
    
    print_status "Exporting Zephyr..."
    west zephyr-export
    
    print_success "ZMK workspace setup complete!"
    print_status "Next steps:"
    echo "  1. Copy your zmk-config to the workspace:"
    echo "     cp -r /Users/proctoi/Documents/Coding/custom-keyboard/zmk-config $workspace_dir/"
    echo "  2. Navigate to zmk-config:"
    echo "     cd $workspace_dir/zmk-config"
    echo "  3. Run the build script:"
    echo "     ./build.sh"
}

# Main execution
main() {
    print_status "Starting ZMK build process..."
    
    # Check if we're in the right directory
    if [[ ! -f "build.yaml" ]]; then
        print_error "build.yaml not found. Please run this script from your zmk-config directory."
        exit 1
    fi
    
    # Check if we're in a ZMK workspace
    check_zmk_workspace
    
    # Parse configurations
    print_status "Parsing build.yaml..."
    local configs=($(parse_build_yaml))
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        print_error "No configurations found in build.yaml"
        exit 1
    fi
    
    print_success "Found ${#configs[@]} configuration(s) to build"
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    
    # Build each configuration
    local failed_builds=0
    for config in "${configs[@]}"; do
        IFS='|' read -r board shield artifact <<< "$config"
        
        if ! build_config "$board" "$shield" "$artifact"; then
            failed_builds=$((failed_builds + 1))
        fi
        
        echo  # Add spacing between builds
    done
    
    # Summary
    echo
    print_status "Build Summary:"
    print_success "Total configurations: ${#configs[@]}"
    if [[ $failed_builds -eq 0 ]]; then
        print_success "Successful builds: ${#configs[@]}"
        print_success "Failed builds: 0"
    else
        print_error "Successful builds: $((${#configs[@]} - failed_builds))"
        print_error "Failed builds: $failed_builds"
    fi
    
    # List built firmwares
    echo
    list_firmwares
    
    # Exit with error if any builds failed
    if [[ $failed_builds -gt 0 ]]; then
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    "clean")
        clean_builds
        ;;
    "list")
        list_firmwares
        ;;
    "setup")
        setup_zmk_workspace
        ;;
    "help"|"-h"|"--help")
        echo "ZMK Build Script"
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  Build all configurations from build.yaml"
        echo "  setup      Set up ZMK workspace (run this first)"
        echo "  clean      Clean all build directories"
        echo "  list       List all built firmware files"
        echo "  help       Show this help message"
        echo ""
        echo "Setup Instructions:"
        echo "  1. Run: $0 setup"
        echo "  2. Copy your zmk-config to the created workspace"
        echo "  3. Run: $0"
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown command: $1"
        print_error "Use '$0 help' for usage information"
        exit 1
        ;;
esac