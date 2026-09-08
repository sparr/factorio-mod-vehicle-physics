--- Cars stop dead with a screech in vanilla, which fights the drifting this mod is for,
--- so the trigger is taken off everything that is not a tank.
---
--- This runs in data-final-fixes because it has to see every car every mod adds, and
--- info.json carries a hidden optional dependency on each vehicle mod known to add one.
--- That is not tidiness: mods are ordered by their dependencies, and a mod that declares
--- its cars in its own data-final-fixes would otherwise be free to run after this one and
--- keep its stop trigger. The list can only ever be as complete as the day it was written.
for name, prototype in pairs(data.raw.car) do
	if not name:find("tank") then
		prototype.stop_trigger = nil
	end
end
