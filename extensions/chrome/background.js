// Judge Chronos - Background Script
// Handles native messaging with the macOS app

// Native messaging host name (must match Info.plist)
const NATIVE_HOST_NAME = 'com.berkerceylan.judgechronos.browser';

// Track connection state
let nativePort = null;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = 5;

// Track active tabs per window
const activeTabs = new Map();

// Connect to native host
function connectToNativeHost() {
  if (nativePort) {
    console.log('[Judge Chronos] Already connected');
    return;
  }
  
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    console.error('[Judge Chronos] Max reconnection attempts reached');
    return;
  }
  
  try {
    console.log('[Judge Chronos] Connecting to native host...');
    nativePort = chrome.runtime.connectNative(NATIVE_HOST_NAME);
    
    nativePort.onMessage.addListener((message) => {
      console.log('[Judge Chronos] Received from host:', message);
      handleNativeMessage(message);
    });
    
    nativePort.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError;
      if (error) {
        console.error('[Judge Chronos] Native host disconnected:', error.message);
      }
      nativePort = null;
      reconnectAttempts++;
      
      // Try to reconnect after delay
      if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
        setTimeout(connectToNativeHost, 5000 * reconnectAttempts);
      }
    });
    
    reconnectAttempts = 0;
    console.log('[Judge Chronos] Connected to native host');
    
    // Send initial heartbeat
    sendToHost({
      type: 'CONNECTED',
      browser: 'chrome',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('[Judge Chronos] Failed to connect:', error);
    reconnectAttempts++;
  }
}

// Send message to native host
function sendToHost(message) {
  if (!nativePort) {
    console.log('[Judge Chronos] Not connected, attempting to connect...');
    connectToNativeHost();
    return false;
  }
  
  try {
    nativePort.postMessage(message);
    return true;
  } catch (error) {
    console.error('[Judge Chronos] Failed to send message:', error);
    nativePort = null;
    return false;
  }
}

// Handle messages from native host
function handleNativeMessage(message) {
  switch (message.type) {
    case 'PING':
      sendToHost({ type: 'PONG', timestamp: new Date().toISOString() });
      break;
      
    case 'GET_ACTIVE_TAB':
      chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
        if (tabs[0]) {
          sendToHost({
            type: 'ACTIVE_TAB',
            url: tabs[0].url,
            title: tabs[0].title
          });
        }
      });
      break;
  }
}

// Handle messages from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('[Judge Chronos] Message from content script:', message.type);
  
  // Add tab ID to message
  if (sender.tab) {
    message.tabId = sender.tab.id;
  }
  
  switch (message.type) {
    case 'PAGE_UPDATE':
      // User is on this page - send to native host
      sendToHost({
        type: 'URL_ACTIVE',
        browser: 'chrome',
        url: message.url,
        title: message.title,
        domain: message.domain,
        timestamp: message.timestamp,
        tabId: message.tabId,
        windowFocused: message.windowFocused
      });
      break;
      
    case 'PAGE_HIDDEN':
      // Tab hidden but still open
      sendToHost({
        type: 'URL_INACTIVE',
        browser: 'chrome',
        url: message.url,
        timestamp: message.timestamp
      });
      break;
      
    case 'PAGE_BLUR':
      // Window lost focus
      sendToHost({
        type: 'BROWSER_BLUR',
        browser: 'chrome',
        timestamp: message.timestamp
      });
      break;
  }
  
  sendResponse({ received: true });
  return true; // Keep channel open for async
});

// Track active tab changes
chrome.tabs.onActivated.addListener((activeInfo) => {
  chrome.tabs.get(activeInfo.tabId, (tab) => {
    if (chrome.runtime.lastError) return;
    
    console.log('[Judge Chronos] Tab activated:', tab.url);
    
    // Extract domain
    let domain = tab.url;
    try {
      const url = new URL(tab.url);
      domain = url.hostname.replace(/^www\./, '');
    } catch (e) {
      // Invalid URL, skip
      return;
    }
    
    sendToHost({
      type: 'URL_ACTIVE',
      browser: 'chrome',
      url: tab.url,
      title: tab.title,
      domain: domain,
      timestamp: new Date().toISOString(),
      tabId: activeInfo.tabId,
      windowFocused: true
    });
  });
});

// Track tab updates (URL changes)
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.active) {
    console.log('[Judge Chronos] Tab updated:', tab.url);
    
    let domain = tab.url;
    try {
      const url = new URL(tab.url);
      domain = url.hostname.replace(/^www\./, '');
    } catch (e) {
      return;
    }
    
    sendToHost({
      type: 'URL_ACTIVE',
      browser: 'chrome',
      url: tab.url,
      title: tab.title,
      domain: domain,
      timestamp: new Date().toISOString(),
      tabId: tabId,
      windowFocused: true
    });
  }
});

// Track tab closure
chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  sendToHost({
    type: 'TAB_CLOSED',
    browser: 'chrome',
    tabId: tabId,
    timestamp: new Date().toISOString()
  });
});

// Track window focus
chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) {
    // All windows lost focus
    sendToHost({
      type: 'BROWSER_BLUR',
      browser: 'chrome',
      timestamp: new Date().toISOString()
    });
  } else {
    // Window gained focus - get active tab
    chrome.tabs.query({ active: true, windowId: windowId }, (tabs) => {
      if (tabs[0]) {
        let domain = tabs[0].url;
        try {
          const url = new URL(tabs[0].url);
          domain = url.hostname.replace(/^www\./, '');
        } catch (e) {
          return;
        }
        
        sendToHost({
          type: 'URL_ACTIVE',
          browser: 'chrome',
          url: tabs[0].url,
          title: tabs[0].title,
          domain: domain,
          timestamp: new Date().toISOString(),
          tabId: tabs[0].id,
          windowFocused: true
        });
      }
    });
  }
});

// Initialize on startup
chrome.runtime.onStartup.addListener(() => {
  console.log('[Judge Chronos] Extension started');
  connectToNativeHost();
});

chrome.runtime.onInstalled.addListener(() => {
  console.log('[Judge Chronos] Extension installed');
  connectToNativeHost();
});

// Initial connection
connectToNativeHost();
