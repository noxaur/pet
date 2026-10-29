# pet

Clawd is a small orange pixel creature who lives on your desktop. He walks on the floor of each display and on the tops of your windows. He naps when you are away and watches your cursor. Sometimes he makes mischief.

- **Drag**: he grabs a window and pulls it a few hundred points, or rides on top of it. A tiled CatWM window is floated first. About three minutes later he puts it back in its tile.
- **Fetch**: he jumps through a portal to another Desktop, finds a window, and carries it back to your Desktop. This uses CatWM `workspace` and `movetoworkspace`. About three minutes later he sends it home with `movetoworkspacesilent`, and you stay on your Desktop.
- When Clawd quits, he re-tiles each window he floated and sends each borrowed window home.

Pick him up and throw him. Click him, double-click him, or click him five times fast. From mid-October to 1 November he sometimes haunts your windows as a ghost.

While you use the Claude app, he sits down at his laptop and types along. He packs up when you switch to another app or Desktop. With the Claude app installed he plays its official laptop animation, read from the app at launch and not shipped with Clawd; without it he draws his own.

## Install

Download `Clawd-<version>.zip` from the [latest release](https://github.com/noxaur/pet/releases/latest), unzip it and move `Clawd.app` to Applications. Clawd is not notarized. The first time you open him, macOS blocks him: open System Settings › Privacy & Security and click Open Anyway.

Clawd updates himself with [Sparkle](https://sparkle-project.org). He looks for a new release one time each day, downloads it and installs it when he quits. To look now, use "Check for Updates…" in the menu bar.

## Run

You need macOS 14 or later and the Swift toolchain (Xcode or the Command Line Tools).

```sh
git clone https://github.com/noxaur/pet.git
cd pet
./build.sh --install   # builds build/Clawd.app, copies it to ~/Applications and opens it
```

The first time, Clawd opens System Settings and shows you how to give Accessibility access. Clawd needs it to move windows. To do this later, use "Grant Accessibility Access…" in the menu bar. To fetch windows from other Desktops, the CatWM tiling window manager must run. Without CatWM he still walks, plays and drags windows on the current Desktop.

## Control

The menu bar icon has Drag, Fetch, Give Everything Back, Party, Mischief (on or off), Hide and Quit. A shell can run a behaviour in the running Clawd:

```sh
build/Clawd.app/Contents/MacOS/Clawd do fetch
```

The behaviours are `drag`, `fetch`, `giveback`, `party`, `stroll`, `look`, `climb`, `think`, `peek`, `dance`, `sneeze`, `nap`, `curious`, `haunt`, `flip`, `giggle`, `hello` and `code`.

## Code

- `Sprite.swift`: the 12 × 8 pixel body of the official art, the poses and the hats.
- `Clawd.swift`: the panel, the physics on floors and window tops, and the awaitable moves.
- `Brain.swift`: the behaviours, the drag and the fetch.
- `World.swift`: the window list, the surfaces Clawd can stand on, and AX window moves.
- `Desk.swift`: a small client for the CatWM control socket.
- `Effects.swift`: the confetti and the portal.
- `Official.swift`: loads the official laptop animation from the installed Claude app.
- `Permissions.swift`: Accessibility access with [PermissionFlow](https://github.com/noxaur/PermissionFlow).
- `Updates.swift`: Sparkle updates.

## Release

Each push to `main` makes a release. The `Release` workflow builds Clawd, signs the zip with the Sparkle EdDSA key in the `SPARKLE_PRIVATE_KEY` secret, and publishes the zip and `appcast.xml` as a GitHub release. The build number is the commit count on `main`. Pull requests do not make a release.

Clawd is a fan project. It is not made by Anthropic or affiliated with Anthropic.
