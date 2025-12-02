#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>
#include <string_view>
#include <cstdlib>

// Copyright (c) Killian Zabinsky
// All rights reserved.

// You may modify this file for personal use only.
// Redistribution in any form is strictly prohibited
// without express written permission from the author.

// Notes for later:
// - pack.vor file for package information (devs required to include)

static constexpr char VERSION[] = "0.0.1";

std::ofstream dvorcore;

static std::string home_dir() {
    if (const char* h = std::getenv("HOME")) return std::string(h);
    return ".";
}

static void cmd_version() {
    std::cout << "Vorcore " << VERSION << "\n";
}

static void cmd_help() {
    std::cout << "Vorcore [" << VERSION << "] - Vorosium Core Package Manager\n";
    std::cout << "Usage: ...\n\n";
}

int install() {
    // Installation logic here
    return 0;
}

int update() {
    // Update logic here
    return 0;
}

int list() {
    // List logic here
    return 0;
}

int autoDriver() {
    // Auto driver logic here
    return 0;
}

int search() {
    // Search logic here
    return 0;
}

int checkActions(int argc, char** argv) {
    // User didn't provide arguments
    if (argc < 2) { cmd_help(); return 1; }

    // Retrieve command-line arguments
    std::string_view arg1 = argv[1];
    // Removes potential null pointer issues with only one argument
    std::string_view arg2 = (argc > 2 && argv[2] != nullptr) ? argv[2] : std::string_view{};

    if (arg1 == "help") { cmd_help(); return 0; }
    if (arg1 == "version") { cmd_version(); return 0; }
    if (arg1 == "install") { install(); return 0; }
    if (arg1 == "update") { update(); return 0; }
    if (arg1 == "list") { list(); return 0; }
    if (arg1 == "autodriver") { autoDriver(); return 0; }
    if (arg1 == "search") { search(); return 0; }

    std::cerr << "Unknown command: " << arg1 << "\n";
    cmd_help();
    return 0;
}

int main(int argc, char** argv) {


    std::string homeDir = home_dir();
    // Set path to data.vorcore in home directory
    std::filesystem::path vorcore_path = std::filesystem::path(homeDir) / "data.vorcore";

    if (std::filesystem::exists(vorcore_path)) {
        // Continue with normal operation
        checkActions(argc, argv);
        return 0;
    }

    std::cerr << "Error: dat.vorcore file not found in home directory\n";
    std::cout << "Installing Vorcore...\n";
    // Create file
    dvorcore.open(vorcore_path, std::ios::out);
    if (!dvorcore) {
        std::cerr << "Error: Failed to create data.vorcore file\n";
        std::cout << "\n";
        return 1;
    }
    
    std::cout << "Vorcore installed successfully at " << vorcore_path << "\n";
    dvorcore.close();
    // Continue with normal operation
    checkActions(argc, argv);
    return 0;
}