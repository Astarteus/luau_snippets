-- Using AstasCast

-- # SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local RS = game:GetService('ReplicatedStorage')

-- # MODULES
local AstasCast = require(RS.AstasCast)

task.wait(6) -- Let roblox studio load :) 

-- # INIT SETTINGS
local Caster = AstasCast.Create({
	MaxDistance = 800, -- Self explanatory
	SegmentLength = .6, -- If velocity value is relatively high (100/150+) you should increment this value for a better optimization
	-- ^^ only affects the amount of raycasts, not the bullet's position
	ViewTrajectory = true, -- Creates a bunch of part that show the trajectory (recommended if testing only)
	
	-- DO NOT SKIP
	RayParams = {
		FilterType = Enum.RaycastFilterType.Exclude, -- Exclude / Inclue (DO NOT ATTEMPT TO USE Blacklist / Whitelist)
		FilterDescendants = {},
		RespectCanCollide = false, -- [OPTIONAL]
		IgnoreWater = true, -- [OPTIONAL]

		MaxHits = math.huge, -- How many hits can the bullet receive?
	},

	-- [OPTIONAL]
	-- If no CustomBullet is specified you can create your own bullet and modify it's position using [Motion.Moved] event
	CustomBulletModel = workspace.Shape, -- Explorer location of the bullet that will be cloned
	CustomBulletContainer = workspace, -- Bullet's parent
	CustomBulletFeatures = {
		Attributes = {
			['PlayerName'] = 'Astarteus'
			-- ^^ NAME        ^^ VALUE
		},
		Tags = {
			'Astarteus'
		},
		
		DestructionDelay = 0.5, -- Motion terminated -> wait 0.5 -> destroy bullet
	}
})

-- # MAIN METHOD
local Motion = Caster:Fire(
	Vector3.new(0,10,0), -- Starting position
	Vector3.new(0,0,1), -- LookVector (normalized/unit vector) based on the origin: +1 stud on the X axis added to the origin, V3.new(1,40,0))
	70, 
	Vector3.new(10,0,0) -- if nil -> Vector3.new()
)

print(Motion:GetState()) -- "Running"
local Bullet = Motion.Info.Bullet

-- # CONNECTIONS
Motion.Moved:Connect(function(Position)
	--print('No need to move the bullet since we have already declared a custom one!')
end)

Motion.Hit:Connect(function(Hit)
	print(Bullet.Name..' collided with '..Hit.instance.Name)
end)

Motion.Ended:Connect(function(RayHits)
	print(Motion:GetState()) -- "Ended"
end)

task.wait(2.25)
Motion:Pause()
print(Motion:GetState()) -- "Paused"

task.wait(2)
Motion:Resume()
print(Motion:GetState()) -- "Running"
