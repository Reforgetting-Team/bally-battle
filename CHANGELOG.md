# changelog

## 1.1.2 — lots of little fixes

we did a pass over the game and cleaned up a bunch of bugs, from camera shake and mobile input to saved settings and multiplayer cleanup.

- **camera and effects:** camera shake now fully resets after it ends, background layers don't duplicate in the editor, and the wind trail lines up properly with a smoother gradient.
- **controls:** mobile button presses stay registered across high refresh rates, the buttons can show during desktop testing, and opening the pause menu now stops gameplay inputs. Wall bounces also play their sound again.
- **menus and HUD:** transitions handle missing nodes and callbacks safely, the debug HUD stays in the corner on different screen sizes, and it now shows when you're cooking a bomb.
- **settings:** master and music volume save between sessions, apply as you move the sliders, and corrupted power loadouts are kept to the usual three slots.
- **multiplayer and matches:** resolved bomb data clears between games, disconnects don't reload a lobby you're already in, empty bomb IDs can't clear other bombs, and match timers stop cleanly when leaving a scene. Tutorial rounds now bring you back after a knockout.
- **bombs and player data:** bomb cleanup checks IDs safely, victim IDs use the right type, and rolling bombs handle a missing sprite without errors.

## 1.1.1 — lil fixes n new stuff

we gave the controls and menus a little polish, fixed up some map stuff, and put a practice buddy in the tutorial so u can test powers without waiting for a friend to join.

- **practice dummy:** tutorial targets play the full death pop, then come back with the spawn pop. duplicate them in the tutorial scene to add more.
- **mobile controls:** round joystick, game-style buttons, and proper mouse support when u plug one in. keyboard still works too.
- **bombs:** they now make a higher-pitched version of bally's bounce sound when they hit the floor.
- **the world:** terrain uses the new wider art without clipping, tile collisions are shared and consistent, and the clouds keep drifting across scene changes.
- **multiplayer:** players get their lobby loadout before they appear, and match scene changes wait for everyone to load in.
- **menus:** the Done button got the new button art, and the tutorial spells out the controls for both touch and keyboard/mouse.

## 1.0.0 — hey, we made it

so this is the first stable release of bally battle. the core game loop is in, the menus have their buttons, and you can actually find your friends on the same network now.

- **playing together:** a host can show up as a nearby LAN room, and the lobby lets you join it. the host keeps rounds and explosions in sync so everyone stays in the same match.
- **the bomb:** it bounces around, then blows up. players near the edge still get punted by the blast, even when it isn't enough to take them out.
- **the camera and getting bonked:** the camera follows the action and can shake on a blast. when a player gets knocked out, they freeze, go gray, do a little shake, and pop away with their text.
- **mobile controls:** the controls move with the screen layout, the joystick can aim a held bomb, and tapping around the screen doesn't accidentally dash. there's also a pause button up top where your thumb can get it.
- **menus and tutorial:** the pause menu has continue, settings, and a way back to the main menu. opening settings doesn't pause an online match. the tutorial explains the powers, works for mobile, and has a back button.
- **the world:** the menus and levels get their backgrounds back, and the game has its little presentation touches like music and the camera framing.

that's the big stuff for 1.0.0. now go bonk your friends.
