# Reusable PowerShell helpers for visually checking the running Calendar window.
# Dot-source this file first:  . .\tools\screenshot-helpers.ps1
#
# SetProcessDpiAwareness is required before GetWindowRect/CopyFromScreen on any
# display with >100% scaling, otherwise screenshots come out cropped/misaligned.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CalWin32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
try { [CalWin32]::SetProcessDpiAwareness(2) | Out-Null } catch {}

function Get-CalWindow {
    Get-Process | Where-Object { $_.MainWindowTitle -eq "Calendar" } | Select-Object -First 1
}

function Get-CalRect {
    $proc = Get-CalWindow
    $hwnd = $proc.MainWindowHandle
    [CalWin32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
    $rect = New-Object CalWin32+RECT
    [CalWin32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    return $rect
}

function Take-CalScreenshot($path) {
    $rect = Get-CalRect
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($path)
    $graphics.Dispose()
    $bmp.Dispose()
}

function Send-CalWheel($clicks, $notches) {
    # clicks: number of wheel events to send. notches: +120 per "click up" / -120 per "click down".
    $rect = Get-CalRect
    $cx = [int](($rect.Left + $rect.Right) / 2)
    $cy = [int](($rect.Top + $rect.Bottom) / 2)
    [CalWin32]::SetCursorPos($cx, $cy) | Out-Null
    for ($i = 0; $i -lt $clicks; $i++) {
        [CalWin32]::mouse_event(0x0800, 0, 0, $notches, 0) # MOUSEEVENTF_WHEEL
        Start-Sleep -Milliseconds 60
    }
}

function Click-CalAt($xOffset, $yOffset) {
    # Coordinates are PHYSICAL pixels relative to the window's top-left corner.
    $rect = Get-CalRect
    $x = $rect.Left + $xOffset
    $y = $rect.Top + $yOffset
    [CalWin32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 100
    [CalWin32]::mouse_event(0x0002, 0, 0, 0, 0) # left down
    Start-Sleep -Milliseconds 60
    [CalWin32]::mouse_event(0x0004, 0, 0, 0, 0) # left up
}
