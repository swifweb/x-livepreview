# x-livepreview
🖥 Live Preview extension for Xcode

_Find latest compiled app in releases or compile it yourself_

- move the app into your `Applications` folder
- run the app so swift icon will be visible near the clock in the top bar
- go to your swifweb project and create empty `Package.xpreview` file in the root folder near the `Package.swift` file
- add new editor in the right (Ctrl+Cmd+T) and open there the `Package.xpreview`
- then click to your left editor and go to any swift file which contains `WebPreview` and press `Cmd+S` there once

On the right side above the swift logo you will see the yellow circle which indicates that live preview is building now, it may take about a minute for the first time since it is compiling the whole project from scratch. Then when it is finished you will see the preview and circle indicator became green.

Later when you made any changes in the file just hit `Cmd+S` to update livepreview.
When you switch to another file just hit `Cmd+S` inside it to see its livepreview.

Congrats, now you can code your swifweb app in beolved Xcode with an awesome livepreview right inside of it and be super productive! 🚀

