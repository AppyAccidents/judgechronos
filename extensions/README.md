# Judge Chronos Browser Extensions

Browser extensions to track website time and send it to the Judge Chronos app.

## Supported Browsers

- Google Chrome (Manifest V3)
- Safari (Web Extension API)
- Firefox (coming soon)

## Chrome Extension

### Installation (Development)

1. Open Chrome and navigate to `chrome://extensions/`
2. Enable "Developer mode" in the top right
3. Click "Load unpacked"
4. Select the `extensions/chrome` folder
5. The extension should now be installed

### Installation (Production - Chrome Web Store)

Coming soon...

## Safari Extension

### Installation

The Safari extension is bundled with the Judge Chronos macOS app:

1. Install Judge Chronos from the Mac App Store or directly
2. Open Safari Preferences → Extensions
3. Enable "Judge Chronos Extension"
4. Grant permissions when prompted

### Building from Source

1. Open `extensions/safari/Judge Chronos Extension.xcodeproj` in Xcode
2. Build and run the extension target
3. Safari will prompt you to enable the extension

## How It Works

### Native Messaging

The extensions communicate with the Judge Chronos app using **Native Messaging**:

```
Browser Extension → Native Host → Judge Chronos App
```

### Data Tracked

- **URL**: The current webpage URL
- **Domain**: Extracted domain (e.g., "github.com")
- **Page Title**: Document title
- **Active Time**: Time spent on each site
- **Focus State**: Whether the browser/tab is active

### Privacy

- All data is processed locally
- No data is sent to external servers
- URLs are analyzed on-device for productivity scoring
- You can pause tracking at any time via the extension popup

## Extension Architecture

### Chrome Extension

```
manifest.json       # Extension configuration
background.js       # Service worker for native messaging
content.js          # Injected into every page
popup.html/js       # Extension popup UI
```

### Safari Extension

Uses Safari's Web Extension API which is compatible with Chrome's extension format.

## Message Types

### From Extension to App

| Type | Description |
|------|-------------|
| `URL_ACTIVE` | User is viewing this URL |
| `URL_INACTIVE` | Tab hidden but still open |
| `BROWSER_BLUR` | Browser window lost focus |
| `TAB_CLOSED` | Tab was closed |
| `CONNECTED` | Extension connected to native host |

### From App to Extension

| Type | Description |
|------|-------------|
| `PING` | Keep-alive check |
| `GET_ACTIVE_TAB` | Request current tab info |

## Development

### Testing

1. Build and run Judge Chronos app
2. Install the browser extension
3. Open browser console to see debug messages
4. Check Judge Chronos Browser Extension settings

### Debug Logs

Enable debug logging in browser console:

```javascript
// Chrome
localStorage.setItem('jc-debug', 'true');

// Check connection
chrome.runtime.sendMessage({ type: 'PING' });
```

## Troubleshooting

### Extension not connecting to app

1. Ensure Judge Chronos app is running
2. Check that native messaging host is registered:
   - Look for `com.berkerceylan.judgechronos.browser.json` in `/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
3. Check browser console for errors
4. Try reloading the extension

### URLs not appearing in timeline

1. Check extension permissions (should have access to all sites)
2. Verify "Track Browser History" is enabled in Judge Chronos settings
3. Ensure the domain is not in the exclusion list

## License

MIT License - Same as Judge Chronos app
