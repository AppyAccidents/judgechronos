// Judge Chronos - Popup Script

document.addEventListener('DOMContentLoaded', async () => {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const siteName = document.getElementById('siteName');
  const siteUrl = document.getElementById('siteUrl');
  const sessionTime = document.getElementById('sessionTime');
  const todayTime = document.getElementById('todayTime');
  const openAppBtn = document.getElementById('openApp');
  const pauseBtn = document.getElementById('pauseTracking');
  
  let isPaused = false;
  let sessionStartTime = Date.now();
  
  // Format time display
  function formatTime(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    
    if (hours > 0) {
      return `${hours}:${remainingMinutes.toString().padStart(2, '0')}`;
    }
    return `${minutes}:${(seconds % 60).toString().padStart(2, '0')}`;
  }
  
  // Get current tab info
  async function getCurrentTab() {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    return tabs[0];
  }
  
  // Update display
  async function updateDisplay() {
    try {
      const tab = await getCurrentTab();
      
      if (tab) {
        siteName.textContent = tab.title || 'Unknown';
        
        // Extract domain
        try {
          const url = new URL(tab.url);
          siteUrl.textContent = url.hostname.replace(/^www\./, '');
        } catch {
          siteUrl.textContent = tab.url || '-';
        }
      }
      
      // Update session time
      if (!isPaused) {
        sessionTime.textContent = formatTime(Date.now() - sessionStartTime);
      }
      
    } catch (error) {
      console.error('[Judge Chronos Popup] Error:', error);
    }
  }
  
  // Check connection status
  function checkStatus() {
    // Try to ping the background script
    chrome.runtime.sendMessage({ type: 'PING' }, (response) => {
      if (chrome.runtime.lastError) {
        statusDot.classList.add('disconnected');
        statusText.textContent = 'Not connected';
      } else {
        statusDot.classList.remove('disconnected');
        statusText.textContent = 'Connected to app';
      }
    });
  }
  
  // Open app button
  openAppBtn.addEventListener('click', () => {
    // This would open the Judge Chronos app
    // On macOS, use a custom URL scheme
    window.open('judgechronos://open', '_blank');
  });
  
  // Pause button
  pauseBtn.addEventListener('click', () => {
    isPaused = !isPaused;
    pauseBtn.textContent = isPaused ? 'Resume' : 'Pause';
    
    chrome.runtime.sendMessage({
      type: isPaused ? 'PAUSE_TRACKING' : 'RESUME_TRACKING'
    });
  });
  
  // Initial update
  updateDisplay();
  checkStatus();
  
  // Update timer every second
  setInterval(updateDisplay, 1000);
});
