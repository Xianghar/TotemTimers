_G["BINDING_HEADER_TOTEMTIMERSHEADER"] = "TotemTimers"
_G["BINDING_NAME_TOTEMTIMERSAIR"] = "Cast active air totem"
_G["BINDING_NAME_TOTEMTIMERSAIRMENU"] = "Open air totem menu"
_G["BINDING_NAME_TOTEMTIMERSEARTH"] = "Cast active earth totem"
_G["BINDING_NAME_TOTEMTIMERSEARTHMENU"] = "Open earth totem menu"
_G["BINDING_NAME_TOTEMTIMERSEARTHSHIELDLEFT"] = "Earth Shield Leftclick"
_G["BINDING_NAME_TOTEMTIMERSEARTHSHIELDMIDDLE"] = "Earth Shield Middleclick"
_G["BINDING_NAME_TOTEMTIMERSEARTHSHIELDRIGHT"] = "Earth Shield Rightclick"
_G["BINDING_NAME_TOTEMTIMERSEARTHSHIELDBUTTON4"] = "Earth Shield Button 4"
_G["BINDING_NAME_TOTEMTIMERSFIRE"] = "Cast active fire totem"
_G["BINDING_NAME_TOTEMTIMERSFIREMENU"] = "Open fire totem menu"
_G["BINDING_NAME_TOTEMTIMERSWATER"] = "Cast active water totem"
_G["BINDING_NAME_TOTEMTIMERSWATERMENU"] = "Open water totem menu"
_G["BINDING_NAME_TOTEMTIMERSWEAPONBUFF1"] = "Weapon Buff 1"
_G["BINDING_NAME_TOTEMTIMERSWEAPONBUFF2"] = "Weapon Buff 2"

local L = LibStub("AceLocale-3.0"):NewLocale("TotemTimers", "enUS", true, true)
if not L then return end

L["Air Button"] = true
L["Cooldown"] = true
L["Ctrl-Leftclick to remove weapon buffs"] = true
L["Delete Set"] = "Delete Totem Set %s?"
L["Earth Button"] = true
L["Fire Button"] = true
L["GamePad Tutorial Title"] = "TotemTimers GamePad Tutorial"
-- tutorial texts: {PAD...} is replaced by the icon of that gamepad button, {spell:...} by the name of a spell of TotemTimers.SpellIDs
L["GamePad Tutorial Bar"] = "While you hold the trigger button {PADLTRIGGER} + {PADRTRIGGER}, the gamepad UI shows its action bar below. TotemTimers takes over the buttons of this bar. The actions you placed on these buttons can't be used while TotemTimers uses them."
L["GamePad Tutorial Totem Buttons"] = "The face buttons cast your totems:\n\n{PAD1}  Cast earth totem\n{PAD3}  Cast fire totem\n{PAD4}  Cast water totem\n{PAD2}  Cast air totem\n\nThe buttons show your totems and their remaining time."
L["GamePad Tutorial Totem Wheel"] = "Hold a totem button to open a radial menu with all totems of its element.\n\nChoose a totem with a stick and release the button to cast it."
L["GamePad Tutorial Sticky Wheel"] = "If you release the button without choosing a totem, the radial menu stays open:\n\n{PAD1}  Cast the selected totem\n{PAD3}  Set the selected totem as the totem of the button, the menu stays open\n{PAD2}  Close the menu\n\nWhile the menu is open, the sticks choose a totem and don't move your character or the camera."
L["GamePad Tutorial Weapon Wheel"] = "Hold {PADDUP} to open a radial menu with your weapon enchants. Choose an enchant with a stick and release {PADDUP} to put it on your main hand weapon.\n\nLike the totem menus, it stays open if you release the button without choosing an enchant. {PAD3} then sets the selected enchant as the enchant of {PADDUP}."
L["GamePad Tutorial Multicast Wheel"] = "Hold {PADDRIGHT} to open a radial menu with your multicast spells. Choose a spell with a stick and release {PADDRIGHT} to cast it.\n\nLike the totem menus, it stays open if you release the button without choosing a spell. {PAD3} then sets the selected spell as the spell of {PADDRIGHT}."
L["GamePad Tutorial DPad Buttons"] = "The d-pad buttons:\n\n{PADDUP}  Cast the selected weapon enchant\n{PADDRIGHT}  Cast the selected multicast spell\n{PADDDOWN}  {spell:TotemicRecall}\n{PADDLEFT}  {spell:TotemicCall}"
L["GamePad Tutorial Intro"] = "This tutorial shows how TotemTimers integrates into the gamepad UI.\n\nDuring the tutorial, the trigger button is set to {PADLTRIGGER} + {PADRTRIGGER}. Your setting is restored when the tutorial ends."
L["GamePad Tutorial Prompt"] = "You have the gamepad UI enabled.\nDo you want to watch a tutorial on how TotemTimers integrates into the gamepad UI?\n\n You can always start the tutorial later from the addon options."
-- the words for left/rightclick in the tooltips, replaced by gamepad button icons while navigating the menus by gamepad
L["Leftclick"] = true
L["Rightclick"] = true
-- help in the totem wheel of the Gamepad UI: %s are the icons of the held face button, LB and RB
L["Totem Wheel Cast Help"] = "Release %s to cast selected totem."
L["Spell Wheel Cast Help"] = "Release %s to cast selected spell."
-- help in the wheel left open after the release: %s are the icons of Cross/A, Square/X and Circle/B
L["Totem Wheel Sticky Help"] = "%s Cast\n%s Set as active totem\n%s Close"
L["Spell Wheel Sticky Help"] = "%s Cast\n%s Set as active spell\n%s Close"
L["Destroy Totem"] = true
L["Leftclick to cast %s"] = true
L["Leftclick to cast spell"] = true
L["Leftclick to load totem set"] = true
L["Leftclick to open totem set menu"] = true
L["Long Cooldown"] = true
L["Maelstrom Notifier"] = "Maelstrom ready!"
L["Middleclick to cast %s"] = true
L["Next leftclick casts %s"] = true
L["Reset"] = "TotemTimers has been reset!"
L["Rightclick to assign both %s and %s to leftclick"] = true
L["Rightclick to assign spell to leftclick"] = true
L["Rightclick to assign totem to timer button"] = true
L["Rightclick to cast %s"] = true
L["Rightclick to delete totem set"] = true
L["Rightclick to save active totem configuration as set"] = true
L["Shield removed"] = "%s removed"
L["Shift-Rightclick to assign spell to middleclick"] = true
L["Shift-Rightclick to assign spell to rightclick"] = true
L["Totem Destroyed"] = "%s has been destroyed."
L["Totem Expired"] = "%s has expired"
L["Totem Expiring"] = "%s about to expire"
L["Water Button"] = true

