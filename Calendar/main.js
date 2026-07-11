const { app, BrowserWindow, ipcMain, Menu, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

ipcMain.handle('get-data-path', () => path.join(app.getPath('userData'), 'calendar-data.json'));

// Small app-level settings file (separate from calendar-data.json) for things that
// aren't calendar data, like the folder the backup dialogs should reopen to next time.
const settingsPath = path.join(app.getPath('userData'), 'settings.json');
function loadSettings() {
  try { return JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) { return {}; }
}
function saveSettings(settings) {
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
}

ipcMain.handle('export-backup', async (event, jsonContent) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  const settings = loadSettings();
  const stamp = new Date().toISOString().slice(0, 10);
  const dir = settings.lastBackupDir || app.getPath('documents');
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    title: 'バックアップを書き出す',
    defaultPath: path.join(dir, `calendar-backup-${stamp}.json`),
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (canceled || !filePath) return { ok: false };
  fs.writeFileSync(filePath, jsonContent);
  settings.lastBackupDir = path.dirname(filePath);
  saveSettings(settings);
  return { ok: true, filePath };
});

let manualWin = null;
ipcMain.handle('open-manual-window', () => {
  if (manualWin && !manualWin.isDestroyed()) {
    manualWin.focus();
    return;
  }
  manualWin = new BrowserWindow({
    width: 420,
    height: 700,
    title: '使い方',
    backgroundColor: '#FFFFFF',
    autoHideMenuBar: true,
    webPreferences: { nodeIntegration: false, contextIsolation: true }
  });
  manualWin.setMenu(null);
  manualWin.loadFile('manual.html');
  manualWin.on('closed', () => { manualWin = null; });
});

ipcMain.handle('import-backup', async (event) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  const settings = loadSettings();
  const dir = settings.lastBackupDir || app.getPath('documents');
  const { canceled, filePaths } = await dialog.showOpenDialog(win, {
    title: 'バックアップを読み込む',
    defaultPath: dir,
    filters: [{ name: 'JSON', extensions: ['json'] }],
    properties: ['openFile']
  });
  if (canceled || !filePaths[0]) return { ok: false };
  try {
    const content = fs.readFileSync(filePaths[0], 'utf8');
    JSON.parse(content);
    settings.lastBackupDir = path.dirname(filePaths[0]);
    saveSettings(settings);
    return { ok: true, content };
  } catch (e) {
    return { ok: false, error: 'invalid' };
  }
});

function createWindow() {
  Menu.setApplicationMenu(null);
  const win = new BrowserWindow({
    width: 1000,
    height: 800,
    backgroundColor: '#FFFFFF',
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });
  win.loadFile('index.html');
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});
