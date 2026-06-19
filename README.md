# CF Leaderboard configuration

The bot is configured through environment variables. Every supported variable is listed in `application.properties` and `.env.example`.

Required variables have no default and the bot cannot start without them.

## Required CFTools configuration

| Environment variable | Default | Description |
|---|---:|---|
| `CFTOOLS_APPLICATION_ID` | none | ***Required***. ID of the CFTools Data API application. |
| `CFTOOLS_APPLICATION_SECRET` | none | ***Required***. Secret of the same CFTools Data API application. |
| `CFTOOLS_SERVER_API_ID` | none | ***Required***. Server API ID from CFTools, normally formatted as a UUID. The application must have an active grant for this server. |

## Discord connection

| Environment variable | Default | Description |
|---|---:|---|
| `DISCORD_APPLICATION_TOKEN` | none | ***Required***. Discord bot token from the Discord Developer Portal. |
| `DISCORD_GUILD_ID` | none | Optional Discord server ID. When present, the command is registered immediately in that server. When absent, the command is registered globally. |
| `DISCORD_CHANNEL_ID` | none | Optional channel ID. When present, the command is executed only in that channel. Attempts from other channels receive a private response linking to the configured channel. When absent, the command works in every channel. |

## Discord behavior

| Environment variable | Default | Accepted values | Description |
|---|---:|---|---|
| `DISCORD_COMMAND_USAGE_LOGGING_ENABLED` | `true` | `true`, `false` | Logs each received slash command with the Discord username, user ID, and channel ID. Set to `false` to disable only command-usage logs. Errors and startup logs remain enabled. |
| `DISCORD_LOCALIZATION_ENABLED` | `true` | `true`, `false` | Enables localized slash-command labels and localized ephemeral responses. English is always the fallback. |
| `DISCORD_RESPONSE_VISIBILITY` | `ephemeral` | `ephemeral`, `public` | `ephemeral` is visible only to the command user and uses their locale when localization is enabled. `public` is visible to the channel and always uses English. Slash-command labels can still be localized. |
| `DISCORD_LEADERBOARD_LIMIT` | `10` | `1`–`100` | Number of leaderboard entries requested from CFTools. |
| `DISCORD_PLAYER_NAME_MAX_LENGTH` | `24` | `4`–`100` | Maximum player-name length. Longer names end with `...`. |
| `DISCORD_KD_FORMAT` | `float` | `float`, `k/d`, `k:d` | `float` displays the calculated ratio, for example `2.5`. Other modes display kills and deaths, for example `5/2` or `5:2`. |
| `DISCORD_EMBED_COLOR` | `black` | name, `#RRGGBB`, `R,G,B` | Embed color. Named values: `blue`, `red`, `green`, `orange`, `yellow`, `purple`, `pink`, `gray`, `grey`, `black`, `white`. RGB channels must be `0`–`255`. Alpha is not supported. |

## Configuration interactions

- Configuration is validated before Discord connects. Missing or malformed values are logged with the relevant environment-variable name and the Discord/CFTools panel where the value can be found. Secret values are never written to logs.
- `DISCORD_CHANNEL_ID` restricts command execution at runtime; Discord may still display `/leaderboard` in other channels. Using it there returns only an ephemeral redirection message and does not call CFTools.
- CFTools API errors such as `bad-secret`, `no-grant`, and an invalid Server API ID include corrective guidance in the console.
- With `DISCORD_RESPONSE_VISIBILITY=ephemeral` and localization enabled, every user receives a private response in their Discord client language.
- With `DISCORD_RESPONSE_VISIBILITY=public`, response content is always English so a shared channel does not contain responses in the command caller's language.
- `DISCORD_LOCALIZATION_ENABLED=false` forces English command labels and English responses.
- If Discord provides an unsupported locale or a translation key is absent from a locale-specific bundle, the base English bundle is used.
- Without a selected statistic, the table contains player name, kills, deaths, and K/D. Selecting a statistic produces a two-column player/statistic table.

## Windows service installation

Run `install-service.bat` from an Administrator-capable Windows account. The batch file requests elevation and starts the interactive PowerShell installer.

For the simplest installation, place these three downloaded files in one directory:

- `cf-leaderboard.exe`
- `install-service.bat`
- `install-service.ps1`

If the EXE is not next to the installer script, it will automatically open a Windows file picker.

The installer:

- installs NSSM through `winget` using package `NSSM.NSSM`,
- validates all required and optional bot settings,
- provides predefined configuration choices,
- automatically uses `cf-leaderboard.exe` from the installer directory; otherwise it opens a file picker,
- copies the executable to `%ProgramFiles%\CF Leaderboard`,
- stores the bot configuration in the NSSM service environment,
- configures automatic startup and restart on failure,
- waits up to 30 seconds for the service to enter the `Running` state,
- shows the service status and complete `logger.log` content if startup fails.
