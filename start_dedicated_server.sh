#!/bin/bash

# Zombie Survival Dedicated Server Launch Script
# This script starts the dedicated game server

# Default configuration
SERVER_NAME="${SERVER_NAME:-Zombie Survival Server}"
SERVER_PORT="${SERVER_PORT:-7777}"
MAX_PLAYERS="${MAX_PLAYERS:-8}"
REGION="${REGION:-us-east}"
MAP="${MAP:-arena_01}"
DIFFICULTY="${DIFFICULTY:-Normal}"
GAME_MODE="${GAME_MODE:-survival}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_EXECUTABLE:-godot}"
PROJECT_PATH="$SCRIPT_DIR"

# Display configuration
echo "============================================"
echo "  Zombie Survival Dedicated Server"
echo "============================================"
echo "Server Name: $SERVER_NAME"
echo "Port: $SERVER_PORT"
echo "Max Players: $MAX_PLAYERS"
echo "Region: $REGION"
echo "Map: $MAP"
echo "Difficulty: $DIFFICULTY"
echo "Game Mode: $GAME_MODE"
echo "============================================"

# Check if Godot is available
if ! command -v $GODOT_EXECUTABLE &> /dev/null; then
    echo "Error: Godot executable not found at: $GODOT_EXECUTABLE"
    echo "Please set the GODOT_EXECUTABLE environment variable"
    exit 1
fi

# Check if project exists
if [ ! -f "$PROJECT_PATH/project.godot" ]; then
    echo "Error: project.godot not found at: $PROJECT_PATH"
    exit 1
fi

# Start the dedicated server
echo "Starting dedicated server..."

$GODOT_EXECUTABLE \
    --path "$PROJECT_PATH" \
    --headless \
    --dedicated \
    --server-name "$SERVER_NAME" \
    --port $SERVER_PORT \
    --max-players $MAX_PLAYERS \
    --region "$REGION" \
    --map "$MAP" \
    --difficulty "$DIFFICULTY" \
    --game-mode "$GAME_MODE"

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "Server exited with code: $EXIT_CODE"
fi

exit $EXIT_CODE
