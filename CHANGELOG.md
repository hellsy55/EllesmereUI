# EllesmereUI

## [v8.7.2](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.7.2) (2026-08-01)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.7.1...v8.7.2) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.7.2  
- Merge pull request #1128 from dfrisone/panel-scale-highdpi  
    fix: scale the options panel and popups to the 1440p reference on high DPI  
- fix: reset the panel scale once on displays above 1440p  
    Seeding only an unset or default panelScale left the users this change  
    exists for stranded. Anyone on 4K who had already raised the slider did  
    so to work around the panel rendering at a fraction of the reference  
    size, so that value is a workaround rather than a preference, and  
    keeping it now strands them on a stale compensation: the default is  
    correct, and popups no longer scale quadratically with it, so the old  
    number is simply too big.  
    Above 1440p the migration therefore overwrites whatever is stored with  
    the corrected default. It fires exactly once, since migrations stamp  
    done and never run again, so any value chosen afterwards is kept.  
    At or below 1440p nothing was ever broken and the seed is 1.0 anyway, so  
    a stored value can only be a genuine preference and is left alone. The  
    one exception stays: residue from the v1 seed (physH/1080) that went out  
    in pre-release branch builds and never in a release.  
    Verified by simulating the body across every combination of display  
    height and stored value, including both tester-residue cases.  
- fix: scale the options panel and popups to the 1440p reference on high DPI  
    Two related defects on anything above 1080p.  
    The options panel is pinned to physical pixels (baseScale =  
    GetScreenWidth()/physW) so it holds a constant physical size and does  
    not follow the UI Scale slider. At 1080p that reads fine; at 4K the same  
    pixel count covers half as much of the display, so the panel arrives  
    unreadably small and the UI Scale slider appears to do nothing to it.  
    Seed panelScale from the display height, with 1440p as the reference  
    look: a panel of H units covers H*panelScale/physH of the screen, so  
    physH/1440 reproduces 1440p's screen fraction anywhere and 4K seeds 1.5  
    to read exactly like a 2K monitor. Floored at 1 so 1080p keeps its  
    current, slightly larger fraction rather than shrinking. Seeded for new  
    installs in Startup and backfilled by a migration for existing ones,  
    both only when the value is unset or an untouched default.  
    Dialog popups sat on a dimmer GetPopupScale had already scaled and then  
    scaled themselves by the same value again. Being children of that  
    dimmer they rendered at ppScale SQUARED, which works out to  
    panelScale^2 * baseScale px per unit instead of panelScale: oversized on  
    every display, and with uiScale in the denominator, LOWERING the UI  
    scale made popups BIGGER. Scale is now applied once, on the dimmer, with  
    each popup carrying only its own relative bump (1, or 1.15 for the intro  
    popups), so px/unit == panelScale and popups match the panel exactly.  
    Left alone deliberately: the \_popupFrames popups, the two raid-frame  
    manager popups and the nameplate filter panel hang off unscaled parents  
    and were never doubled.  
    Also adds ClampPopupToScreen, used by the modal first-install popup.  
    That popup has no Escape route and sits on a click-eating dimmer, so one  
    that overflows the display puts its buttons out of reach entirely; a 4K  
    tester was left unable to reach the game menu. It measures the frame's  
    real effective scale, so it holds regardless of the scale math above it,  
    and only ever shrinks.  
