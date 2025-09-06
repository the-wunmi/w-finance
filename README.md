# DoubleU Finance

**Under Active Development** - This project is currently in active development. Features and APIs may change frequently.

DoubleU Finance is a comprehensive, open-source personal finance application based on [Maybe Finance](https://github.com/maybe-finance/maybe) but is **not affiliated with or endorsed by** Maybe Finance Inc. This fork is designed to help you take control of your financial life. Built with Ruby on Rails and modern web technologies, it provides powerful tools for tracking accounts, transactions, investments, and financial insights.

## Features

- **Multi-Currency Support** - Track accounts and transactions in multiple currencies
- **Account Management** - Manage checking, savings, credit cards, loans, and investment accounts
- **Transaction Tracking** - Categorize and tag transactions with powerful search and filtering
- **Investment Portfolio** - Track trades, holdings, and investment performance
- **AI Financial Assistant** - Get insights and answers about your financial data
- **API Access** - Programmatic access to your data with secure API keys
- **Financial Reports** - Balance sheets, income statements, and custom reports
- **Bank Integrations** - Connect to banks via Plaid and other providers
- **Data Export** - Export all your financial data for backup and analysis

## Tech Stack

- **Backend**: Ruby on Rails 7.2
- **Database**: PostgreSQL
- **Cache/Jobs**: Redis + Sidekiq
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS

## Getting Started

### Prerequisites

- **Docker Desktop** - Installed and running
- **Dev Containers CLI** - `npm install -g @devcontainers/cli`
- **Git** - For version control

### Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/the-wunmi/w-finance
   cd w-finance
   ```

2. **Start the development environment**
   ```bash
   # Start the dev container (builds everything fresh)
   devcontainer up --workspace-folder .
   ```

3. **Enter the container and set up the application**
   ```bash
   # Enter the running container
   devcontainer exec --workspace-folder . bash

   # Set up the application (installs dependencies, sets up database, seeds data)
   bin/setup
   ```

4. **Start the Rails server**
   ```bash
   # Inside the container
   bin/rails server -b 0.0.0.0
   ```

5. **Access the application**
   - Open your browser to `http://localhost:3000`
   - The application will be running with sample data

### Alternative: VS Code Development

If you prefer using VS Code:

1. **Open in VS Code**
   ```bash
   code .
   ```

2. **Install Dev Containers extension** (if not already installed)

3. **Reopen in Container**
   - Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
   - Type: "Dev Containers: Reopen in Container"
   - Wait for the container to build and start

4. **Set up the application**
   ```bash
   # In VS Code terminal
   bin/setup
   bin/rails server -b 0.0.0.0
   ```

## What's Included

The dev container includes:

- **Ruby 3.4.4** with all gems installed
- **Node.js 20** for frontend asset compilation
- **PostgreSQL** database server
- **Redis** for caching and background jobs
- **Sidekiq** worker for background job processing

## Configuration

### Environment Variables

Copy the example environment file and customize as needed:

```bash
cp .env.example .env.local
```

## Contributing

As this project is under active development, contribution guidelines are still being established. Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). See the [LICENSE](LICENSE) file for details.

This fork is based on [Maybe Finance](https://github.com/maybe-finance/maybe) which is also licensed under AGPL-3.0. "Maybe" is a trademark of Maybe Finance Inc. This project is **not affiliated with or endorsed by** Maybe Finance Inc.
