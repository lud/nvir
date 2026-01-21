# Changelog

All notable changes to this project will be documented in this file.

## [0.16.0] - 2026-01-21

### 🚀 Features

- Added before_env_set_all hook and support MFA tuples for hooks

### 🐛 Bug Fixes

- Fix error display config reader

## [0.15.0] - 2025-12-11

### 🚀 Features

- New dotenv file parser implementation with 10x speed and error reporting

### 📚 Documentation

- Fix deprecated functions in documentation

### ⚙️ Miscellaneous Tasks

- Fix bad formatting

## [0.14.0] - 2025-11-20

### 🚀 Features

- [**breaking**] Function given as default values to env! now act as lazy defaults

### 📚 Documentation

- Clarify Nvir philosophy about production environment

## [0.13.4] - 2025-10-11

### ⚙️ Miscellaneous Tasks

- Remove runtime false from install instructions for fly.io

## [0.13.3] - 2025-07-03

### ⚙️ Miscellaneous Tasks

- Update Elixir Github workflow (#21)
- CI cache setup (#24)
- Added deps submission

## [0.13.2] - 2025-03-31

### 🐛 Bug Fixes

- Removed usage of readmix in prod environment

## [0.13.1] - 2025-03-28

### 📚 Documentation

- Fixed documentation errors

## [0.13.0] - 2025-03-28

### 🚀 Features

- Only define functions with 'env' in their name for 'import Nvir'

## [0.12.0] - 2025-03-19

### 🚀 Features

- [**breaking**] Removed the :* tag as it was confusing

### 📚 Documentation

- Document dotenv!/env! independence (#16)

## [0.11.0] - 2025-03-14

### 🚀 Features

- Added a hook to change variables before they are set

### ⚙️ Miscellaneous Tasks

- Fix exemples with custom MIX_ENV
- Remove unknown function in docs
- Update dependabot config (#10)
- Refactor collecting sources

## [0.10.2] - 2025-01-31

### 🐛 Bug Fixes

- Fixed parsed when ending with comment without final newline
- Fixed parsed when ending with comment without final newline

## [0.10.1] - 2025-01-17

### 🐛 Bug Fixes

- Trim trailing whitespace on unquoted strings

## [0.10.0] - 2025-01-16

### 🚀 Features

- [**breaking**] Replace override with overwrite and support custom loaders

### ⚙️ Miscellaneous Tasks

- Update dependabot config (#2)
- Basic CI
- Dummy CI change

## [0.9.4] - 2024-11-25

### 🐛 Bug Fixes

- Support old Elixir versions

## [0.9.3] - 2024-11-18

### 🚀 Features

- Default caster is :string

## [0.9.2] - 2024-11-17

### 📚 Documentation

- Document parsed templates

## [0.9.1] - 2024-11-17

### 📚 Documentation

- Added documentation to all functions

### ⚙️ Miscellaneous Tasks

- Added changelog
- README ordering
- Versionning with mix version

## [0.9.0] - 2024-11-17

### ⚙️ Miscellaneous Tasks

- Initialization of the repository
- Added license

