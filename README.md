# SyncTween

### Created by @creaco - October 30th, 2024  
*Licensed under the GNU GPLv3 License*

---

## Links
- More information on TweenService found [here](https://create.roblox.com/docs/reference/engine/classes/TweenService).
- If you are unfamiliar with how replication works, please look at [this](https://devforum.roblox.com/t/client-replication-101-the-guide-to-replicating-effects-to-clients) DevForum post.
- This project was inspired by [TweenService2](https://github.com/Steadyon/TweenServiceV2), although not built onto it.

---

**SyncTween** is a tweening library designed to facilitate server-to-client animations, with several features that go beyond traditional tweening modules.

## Advantages
1. **Lower Server Load**  
   By handling animations on the client side, SyncTween reduces the processing burden on the server.

2. **Smoother animations**
    Compared to the server, the client runs at a faster clock, meaning the animations will not be "choppy".
    
## Key Features
1. **Syncing Animations**  
   SyncTween allows animations to be synchronized across all clients. Here's the definition of "synchronization":
   - Synchronization ensures that all clients see the animations in the same state at the same time.
   - By default, all tweens will end at the same time.

2. **Custom Animations**  
   You can define custom animations on the client side. Check out the `Custom` module for examples.

3. **Support for Streaming Enabled & Streaming Out**  
   SyncTween works with **Streaming Enabled** and **Streaming Out** via `CollectionService`.

4. **Selective Replication**  
   Make animations visible to selected clients without replicating them to the server. For example, hide a door for User X but keep it visible for others.

## Current Limitations
1. Players receiving a signal can know who else is receiving that same signal.
2. Custom animations cannot be paused.

---

## How to Use SyncTween

To construct a SyncTween, use the following syntax:

```lua
SyncTween.new(
    object: Instance,                                       -- The object you want to animate.
    tweenInfo: (TweenInfo | Helper.TweenArray | string)?,   -- TweenInfo of the animation.
    properties: { [string]: any }?,                         -- Properties you want to animate.
    players: { Player }?,                                   -- Players to animate.
    replicate: boolean?,                                    -- Should the animation be replicated?
    sync: (boolean | number)?,                              -- Synchronization of the animation.
    uuid: string?                                           -- UUID of the animation (optional).
)
```

### Parameter Notes:
- `tweenInfo`: Accepts a `TweenInfo`, a `Helper.TweenArray`, or a `string`.
  - If a string is provided, it will be treated as a custom animation.
  - A `TweenArray` looks like:  
    ```lua
    { Time = 1, EasingStyle = Enum.EasingStyle.Linear, EasingDirection = Enum.EasingDirection.InOut }
    ```
  - It’s recommended to use `TweenInfo` to avoid confusion, the change was necessary for replication purposes.

### Examples:
1. Animate a part's position:
    ```lua
    SyncTween.new(workspace.Part, TweenInfo.new(1), { Position = Vector3.new(0, 10, 0) })
    ```
    This will animate the part to the position `(0, 10, 0)` over 1 second.

2. Animate a color for a specific player:
    ```lua
    SyncTween.new(workspace.Part, nil, { Color = Color3.new(1, 0, 0) }, { Players.Player1 }, false)
    ```
    This will turn the part red only for Player1.

3. Play a custom "Rainbow" animation at 10 FPS:
    ```lua
    SyncTween.new(workspace.Part.Highlight, "Rainbow", nil, nil, nil, 10)
    ```

---

## Global Methods
- `SyncTween.get(object: Instance, player: Player): { Sync }`  
  Retrieve all animations currently playing on the specified object.
  On the client, this will return everything that is playing, on the server, it will return only Syncs that the player can view.

- `SyncTween.fps(freq: number)`  
  Set the FPS (frames per second) for all synchronized animations that don't have a specific framerate.
  (Default: -1) (Uncapped).

---

## SyncTween Class Methods
- `Play()`  
  Start the animation.

- `Pause()`  
  Pause the animation.
  (Does not apply to custom animations)

- `Cancel()`  
  Cancel the animation.

---

## Summary

You can create a SyncTween (or "Sync") using `SyncTween.new()`. This class inherits the usual tween methods (`:Play()`, `:Pause()`, `:Cancel()`) while offering additional configuration options, such as:
- `tweenInfo`
- `players`
- `replicate`
- `sync`
- `uuid`

The module is written in `--!strict` mode, and the `Sync` type is exported for use.