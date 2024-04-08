---------------------------------------
---------------------------------------
---------------------------------------
-- PART THROW

local Replicated = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

local FastCast = require(Replicated:WaitForChild('FastCastRedux'))

local Clicked = false

script.Parent.Activated:Connect(function()
	if Clicked then return end
	Clicked = true
	
	local Character = script.Parent.Parent
	
	local Object = Replicated.Handle:Clone()
	Object.Anchored = true; Object.Parent = workspace
	Object.CFrame = Character.HumanoidRootPart.CFrame*CFrame.new(0,0,-3)

	local Caster = FastCast.new()
	local Behaviour = FastCast.newBehavior()

	local Params = RaycastParams.new()
	Params.FilterDescendantsInstances = {Character}
	Params.FilterType = Enum.RaycastFilterType.Exclude

	Behaviour.RaycastParams = Params
	Behaviour.MaxDistance = 200

	local Origin, Direction = Object.CFrame.Position, Character.HumanoidRootPart.CFrame.LookVector
	local ActiveCast = Caster:Fire(Origin, Direction, 85, Behaviour)

	local LengthChanged, RayHit, Terminated
	local function CloseConnections()
		if LengthChanged then
			LengthChanged:Disconnect()
		end
		if RayHit then
			RayHit:Disconnect()
		end
		if Terminated then
			Terminated:Disconnect()
		end
	end


	local Params = OverlapParams.new()
	Params.FilterDescendantsInstances = {Character}
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.MaxParts = 100
	local Blacklist_ = {Character, Object}

	LengthChanged = Caster.LengthChanged:Connect(function(Caster, LastPoint, _Ray, Displacement)
		Object.CFrame = CFrame.new(LastPoint, LastPoint+_Ray)
	end)

	RayHit = Caster.RayHit:Connect(function(_Ray, _Result: RaycastResult)
		local Part = _Result.Instance
		local Head = Part.Parent:FindFirstChild('Head')
		if Head then
			Head.Size = Head.Size-Vector3.new(1,1,1)
		end
		if Head.Size.Y < 0.25 then
			Head.Parent:Destroy()
		end
		CloseConnections()
		Object:Destroy()
		script.Parent:Destroy()
	end)

	Terminated = Caster.CastTerminating:Connect(function()
		Object:Destroy()
		script.Parent:Destroy()
	end)
end)


---------------------------------------
---------------------------------------
---------------------------------------
-- PARTS SPAWNER

local RunService = game:GetService('RunService')
local Replicated = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local Debris = game:GetService('Debris')

local SPAWN_DELAY = 1.5
local TOOL_INSTANCE = Replicated:WaitForChild('Throw Part')

local function MakePart()
	local Part = Instance.new('Part')
	Debris:AddItem(Part, 12)
	Part.Anchored = true; Part.CanCollide = false
	Part.Size = Vector3.new(1, 1, 1)
	Part.CFrame = workspace.Baseplate.CFrame * CFrame.new(math.random(-50,50),workspace.Baseplate.Size.Y/2+Part.Size.Y/2,math.random(-50,50))
	Part.Parent = workspace
	Part.Touched:Connect(function(HitP)
		local Hum = HitP.Parent:FindFirstChild('Humanoid')
		if Hum then
			local Player = Players:GetPlayerFromCharacter(Hum.Parent)
			if Player then
				TOOL_INSTANCE:Clone().Parent = Player.Backpack
				Part:Destroy()
			end
		end
	end)
	return Part
end

local Clock = os.clock()
RunService.Heartbeat:Connect(function()
	if os.clock() - Clock > SPAWN_DELAY then
		Clock = os.clock()
		MakePart()
	end
end)
