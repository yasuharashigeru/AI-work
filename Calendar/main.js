const { app, BrowserWindow, ipcMain, Menu } = require('electron');
const path = require('path');

ipcMain.handle('get-data-path', () => path.join(app.getPath('userData'), 'calendar-data.json'));

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
