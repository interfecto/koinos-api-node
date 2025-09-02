# Debug Instructions for Koinos Node App

## Current Status
The app now has comprehensive logging and debug features:

### 1. Debug Console
- **Location**: Bottom-left corner of the app window
- **Button Text**: "Show Debug Console" 
- **Function**: Opens a panel showing all backend logs in real-time

### 2. What You Should See:

#### On Welcome Screen:
- Koinos Node title
- Welcome message
- "Get Started" button
- **"Show Debug Console" button in bottom-left corner** (gray button)

#### In Debug Console (when opened):
- Timestamp for each log entry
- Log levels: DEBUG, INFO, WARN, ERROR (color-coded)
- Filter buttons to show only specific log levels
- Auto-scroll toggle
- Clear button to reset logs

### 3. Testing Flow:

1. **Open the app** - You should see the Welcome screen
2. **Click "Show Debug Console"** - Opens the debug panel at bottom
3. **Click "Get Started"** - Watch the logs for:
   - "Starting system requirements check"
   - "Checking for Docker installation" 
   - "Docker found - Docker version X.X.X" (if installed)
   - "Docker daemon not running" (if Docker Desktop isn't started)
   - Specific error messages about what's missing

### 4. Current Docker Issue:
The logs show Docker is installed but the daemon isn't running. The app should:
1. Detect Docker is installed
2. Try to open Docker Desktop automatically
3. Wait for it to start
4. Show progress

### 5. Manual Docker Start:
If Docker doesn't start automatically:
1. Open Docker Desktop manually from Applications
2. Wait for the whale icon in menu bar to stop animating
3. Click "Check Again" in the error message
4. Watch debug console for new status

### 6. What the Logs Tell You:
- **[INFO] Docker found**: Docker is installed correctly
- **[WARN] Docker daemon not running**: Docker Desktop needs to be started
- **[ERROR] Docker is not installed**: Need to install Docker Desktop
- **[DEBUG]**: Detailed paths and commands being checked

The debug console gives you complete visibility into what the app is doing behind the scenes!