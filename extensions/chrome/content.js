// Judge Chronos - Content Script
// Tracks page changes and sends data to background script

(function() {
  'use strict';

  let currentUrl = window.location.href;
  let currentTitle = document.title;
  let lastUpdateTime = Date.now();
  
  // Extract domain from URL
  function extractDomain(url) {
    try {
      const urlObj = new URL(url);
      return urlObj.hostname.replace(/^www\./, '');
    } catch (e) {
      return url;
    }
  }
  
  // Send message to background script
  function sendPageInfo(isActive = true) {
    const message = {
      type: 'PAGE_UPDATE',
      browser: 'chrome',
      url: window.location.href,
      title: document.title,
      domain: extractDomain(window.location.href),
      timestamp: new Date().toISOString(),
      tabId: null, // Will be filled by background script
      windowFocused: isActive && document.visibilityState === 'visible'
    };
    
    try {
      chrome.runtime.sendMessage(message, (response) => {
        if (chrome.runtime.lastError) {
          console.log('[Judge Chronos] Message error:', chrome.runtime.lastError);
        }
      });
    } catch (e) {
      console.error('[Judge Chronos] Failed to send message:', e);
    }
  }
  
  // Handle visibility change (tab switch, minimize)
  function handleVisibilityChange() {
    if (document.visibilityState === 'visible') {
      sendPageInfo(true);
    } else {
      // Page hidden - notify background
      try {
        chrome.runtime.sendMessage({
          type: 'PAGE_HIDDEN',
          browser: 'chrome',
          url: window.location.href,
          timestamp: new Date().toISOString()
        });
      } catch (e) {
        console.error('[Judge Chronos] Failed to send hide message:', e);
      }
    }
  }
  
  // Handle focus/blur
  function handleFocus() {
    sendPageInfo(true);
  }
  
  function handleBlur() {
    try {
      chrome.runtime.sendMessage({
        type: 'PAGE_BLUR',
        browser: 'chrome',
        url: window.location.href,
        timestamp: new Date().toISOString()
      });
    } catch (e) {
      console.error('[Judge Chronos] Failed to send blur message:', e);
    }
  }
  
  // Watch for URL changes (SPA navigation)
  function observeUrlChanges() {
    let lastUrl = location.href;
    
    new MutationObserver(() => {
      const url = location.href;
      if (url !== lastUrl) {
        lastUrl = url;
        console.log('[Judge Chronos] URL changed:', url);
        
        // Wait a moment for the page to update
        setTimeout(() => {
          sendPageInfo(true);
        }, 500);
      }
    }).observe(document, { subtree: true, childList: true });
  }
  
  // Watch for title changes
  function observeTitleChanges() {
    const titleElement = document.querySelector('head > title');
    if (titleElement) {
      new MutationObserver(() => {
        const newTitle = document.title;
        if (newTitle !== currentTitle) {
          currentTitle = newTitle;
          console.log('[Judge Chronos] Title changed:', newTitle);
          sendPageInfo(true);
        }
      }).observe(titleElement, { subtree: true, childList: true, characterData: true });
    }
  }
  
  // Initialize
  function init() {
    console.log('[Judge Chronos] Content script initialized');
    
    // Send initial page info
    sendPageInfo(true);
    
    // Set up event listeners
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleFocus);
    window.addEventListener('blur', handleBlur);
    
    // Observe changes
    observeUrlChanges();
    observeTitleChanges();
    
    // Send heartbeat every 30 seconds while active
    setInterval(() => {
      if (document.visibilityState === 'visible') {
        sendPageInfo(true);
      }
    }, 30000);
  }
  
  // Run initialization
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
