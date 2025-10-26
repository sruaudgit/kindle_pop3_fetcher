# POP3 Fetcher Plugin for Kindle (Koreader)

This plugin allows you to fetch files attached to emails from a dedicated mailbox and save them directly to your Kindle device. It's designed to provide a similar experience to Amazon's Send-to-Kindle service, but with more flexibility.

## Installation

1.  Download the `pop3_fetcher.koplugin` folder.
2.  Copy the entire `pop3_fetcher.koplugin` folder into the `plugins` directory of your Koreader installation on your Kindle.

## Configuration

Before using the plugin, you **must** configure your email settings.

1.  Locate the `pop3_cfg.lua.sample` file within the `pop3_fetcher.koplugin` directory.
2.  Rename `pop3_cfg.lua.sample` to `config.lua`.
3.  Open `config.lua` and edit the following parameters with your email provider's details:
    *   `pop3_server`: Your POP3 server address (e.g. `pop.gmx.com`)
    *   `pop3_port`: The POP3 SSL port (usually `995`)
    *   `username`: Your full email address
    *   `password`: Your email account password or an app-specific password if you use 2FA.
    *   `save_dir`: The local directory on your Kindle where attachments will be saved (e.g., `/mnt/us/ebooks/pop3`)

## Tested Environment

This plugin has primarily been tested with mail sent from **Gmail** to a **GMX** mailbox. While it might work with other providers, compatibility is not guaranteed.

* Kindle Paperwhite GEN10 FW 5.18.1
* Koreader 2025.8
