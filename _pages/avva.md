---
layout: page
title: avva.studio notes
permalink: /avva
---

### Creating a new project

Take a backup of the current project before starting this.

1. Create new project in Unity3D
	- Use 3D Core project template
	- Call it avva.studio_YYYYQ?
1. Close the project
1. Copy over `avvaunity` folder from `Assets` folder of previous project into `Assets` folder of new project.
1. Copy over `avvaunity/ProjectSettings/TagManager.asset` to `ProjectSettings` folder.
1. Open new project.

### Windows: start an application at startup

Create `.bat` file for application, probably like this content
```
cd %USERPROFILE%\avva\APPLICATION\
powershell "./APPLICATION.exe 2>&1 | tee -a APPLICATION.log"
pause
```

#### With popup

`Super + R`, then `shell:startup`

Create shortcut to batch file and move it to the startup directory.

#### Without popup

Open Task Scheduler
Create basic task
Configure for startup on login (probably don't need always?)
Give .bat script as path

https://superuser.com/a/1168592

To debug, enable history: https://pureinfotech.com/enable-task-scheduler-history-windows-11/
