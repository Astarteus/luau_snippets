-- Module made to handle dummy's movements. It does depend on other modules I scripted for a tycoon.
-- I used "AI" term that actually stands for Artificial Intelligence but it doesn't really have much to do with its purpose, it's just a small term I decided to use when I didn't know I was gonna publish this :). 

-- How does it work?:
-- 1. The first step that has to be done is making an AI by calling ":MakeAI()". You give it the type (string) you want the dummy to be, the origin where it is going to spawn and then the Player who owns it
-- 2. As for the next step you are gonna initialize the dummy along with it's movements (only if you want it to move) by typing ":Init()" and ":AsFollower()
-- 3.   ":AsFollower()" is not the only movement type you can choose, there are also:
--        ":AsEnemy()" where the range of the dummy type is checked and if another dummy is close to it then our dummy will stop and call its attacking function.
--        ":AsFollowPart()" where the dummy follows the part given. It also counts the dummies that are currently following the same part and makes the dummy move some studs away from the original position
-- Here a showcase of it: https://gyazo.com/d85d9e345822241289e07fa72b5d923e

-- You may be wondering what local functions actually do but well it's just some more features I added that were useful for the tycoon (e.g. "is_a_inside_b" that checks if a part is inside another part; "get_offsets_from_coords" that gives the offset where the dummy will move to not to collide with other dummies that are following the same part)

local Controlled = {}
Controlled.__index = Controlled

local Replicated = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Pathfinding = game:GetService('PathfindingService')
local Marketplace =game:GetService('MarketplaceService')

local VFXEvent = Replicated.Events.ToClients
local AttackTypes = require(script.Parent.Data.AttackTypes)
local Data = require(script.Parent.Data)

local AIs = {}

local function is_a_inside_b(a, b)
	local t = {
		["Z"] = b.CFrame*CFrame.new(0,0,b.Size.Z/2),
		["X"] = b.CFrame*CFrame.new(b.Size.X/2,0,0)
	}
	local ranges = {}
	for axis, offset in t do
		ranges[axis] = {}
		local o_axis = axis=="Z" and "X" or "Z"
		if o_axis == "Z" then
			ranges[axis].max = (t[axis]*CFrame.new(0,0,b.Size.Z/2)).Position.Z
			ranges[axis].min = (t[axis]*CFrame.new(0,0,-b.Size.Z/2)).Position.Z
		else
			ranges[axis].max = (t[axis]*CFrame.new(b.Size.X/2,0,0)).Position.X
			ranges[axis].min = (t[axis]*CFrame.new(-b.Size.X/2,0,0)).Position.X
		end
	end
	local pass_z = false
	local pass_x = false
	for axis, states in ranges do
		if axis == "X" then
			if a.Position.Z>states.min and a.Position.Z<states.max or a.Position.Z<states.min and a.Position.Z>states.max then
				pass_z = true
			end
		else
			if a.Position.X>states.min and a.Position.X<states.max or a.Position.X<states.min and a.Position.X>states.max then
				pass_x = true
			end
		end
	end
	if pass_z and pass_x then
		return true
	end
end

local function get_offsets_from_coords(Coords: CFrame, Index: number): {[number]: CFrame}
	local Offsets = {}
	if Index == 1 then
		Offsets[Index] = Coords
	else
		local Completed = 1
		local sRange = 5.5
		local Range = sRange
		local Sum = 0
		for i = 1, Index do
			if Sum == 2 then
				Sum = 1
				Completed += 1
				Range = sRange*Completed
			else
				Sum += 1
			end
			local isLeft = i%2==0
			Offsets[i] = Coords*CFrame.new(isLeft and Range or -Range, 0, 0)
		end
	end
	return Offsets
end

local function get_xz(Vector: Vector3)
	return Vector*Vector3.new(1,0,1)
end



function Controlled:Init()
	for _, Part in self.Dummy:GetChildren() do
		if Part:IsA('BasePart') or Part:IsA('MeshPart') then Part.CollisionGroup = self.Owner.Name == 'TestPlayer'  and game.Players:GetChildren()[1].Name or self.Dummy:GetAttribute('Owner') end
	end

	--VFXEvent:FireAllClients("NPC", "MakeHighlight", self.Dummy, self.Dummy, self.Owner)
	local Multiplier = 1
	if self.Owner.Name ~= "TestPlayer" then
		if Marketplace:UserOwnsGamePassAsync(self.Owner.UserId, Data.Gamepasses.SUPER_TROOPS) then
			Multiplier *= 1.5
		end
	end

	self.Dummy.Humanoid.MaxHealth = Data.AttackTypes[self.Type].Health*Multiplier
	self.Dummy.Humanoid.Health = Data.AttackTypes[self.Type].Health*Multiplier
	self.Dummy.Parent = workspace:FindFirstChild(self.Owner.Name..'_Dummies')

	for _, Anim in Replicated.Assets.Animations.NPCs:GetDescendants() do
		local Track = self.Dummy.Humanoid:FindFirstChildOfClass('Animator'):LoadAnimation(Anim)
		table.insert(AIs[self.Dummy].Animations, Track)
	end

	self.Running = false
	self.Dummy.Humanoid.Running:Connect(function(Speed)
		if #self.Waypoints==0 then
			self.Running = false
			self:StopAnimation(self.Type..'_Run')
		elseif #self.Waypoints>0 and not self.Running then
			self.Running = true
			local Anim = self:PlayAnimation(self.Type..'_Run')
			if Data.AttackTypes[self.Dummy:GetAttribute('Type')].Heavy then
				Anim:AdjustSpeed(0.2)
			end
		end
	end)

	self.Dummy.Humanoid.Died:Connect(function()
		self:Terminate()
	end)
end

function Controlled:PlayAnimation(Name)
	for _, Anim in AIs[self.Dummy].Animations do
		if Anim.Name == Name then
			Anim:Play()
			return Anim
		end
	end
end

function Controlled:StopAnimation(Name)
	for _, Anim in self.Dummy.Humanoid:FindFirstChildOfClass('Animator'):GetPlayingAnimationTracks() do
		if Anim.Name == Name then
			Anim:Stop()
			break
		end
	end
end

function Controlled:MakeAI(Type, Origin: CFrame, Owner: Player)
	local self = {}
	setmetatable(self, Controlled)

	self.Type = Type
	self.Owner = Owner
	self.Dummy = Replicated.Assets.NPCs[Type]:Clone()
	self.Dummy:SetAttribute("Owner", Owner.Name)
	self.Dummy:SetAttribute("Type", Type)
	self.Dummy.HumanoidRootPart.CFrame = Origin
	self.Animations = {}
	self.Waypoints = {}
	self.AsFollower_bool = true
	self.AsEnemy_bool = true
	self.AsPartFollower_bool = false
	AIs[self.Dummy] = self

	self:Init()
	return self
end

function Controlled:GetAIs()
	return AIs
end

function Controlled:GetAI(Dummy)
	return AIs[Dummy]
end

function Controlled:SetDestination(Vector, FollowCoords: CFrame)
	if FollowCoords then
		self.Dummy:SetAttribute('OffsetVector', FollowCoords.Position)
		self:FollowOffsetsForNextTarget(Vector, FollowCoords)
	else
		self.Dummy:SetAttribute('OffsetNumber', nil)
		self.Index = 1
		self.Destination = Vector
		self.Waypoints = {{Position = Vector}}
	end
end

function Controlled:ResetDestination()
	self.Destination = nil
	self.Waypoints = {}
	self.Dummy.Humanoid:MoveTo(self.Dummy.HumanoidRootPart.Position)
end

function Controlled:WaitUntilReached()
	repeat 
		RunService.Heartbeat:Wait()
	until #self.Waypoints==0
	return true
end

function Controlled:FollowOffsetsForNextTarget(Vector, Coords: CFrame)
	local MeetingDummies = {}
	local Index = 0
	for _, AI in AIs do
		if #AI.Waypoints>0 and AI.Waypoints[#AI.Waypoints].Position == Coords.Position or AI.Dummy:GetAttribute('OffsetVector') == Coords.Position or AI.Dummy:GetAttribute('OffsetVector') == Vector then
			Index += 1
			AI.Dummy:SetAttribute('OffsetVector', Coords.Position)
			AI.Dummy:SetAttribute('OffsetNumber', Index)
			table.insert(MeetingDummies, AI)
		end
	end
	local Offsets = get_offsets_from_coords(Coords, Index)
	for _, AI in MeetingDummies do
		task.spawn(function()
			--print(Offsets[AI.Dummy:GetAttribute('OffsetNumber')].Position)
			AI:SetDestination(Offsets[AI.Dummy:GetAttribute('OffsetNumber')].Position, nil, true)
		end)
	end
end

function Controlled:GetClosestEnemy()
	local Enemy, Distance = nil, math.huge
	for Dummy, _ in AIs do
		pcall(function()
			if Dummy and Dummy:GetAttribute('Owner') ~= self.Dummy:GetAttribute('Owner') and Dummy.Humanoid.Health ~= 0 then
				local TempDistance = (Dummy.HumanoidRootPart.Position-self.Dummy.HumanoidRootPart.Position).Magnitude
				local DummySpace
				for _, Tycoon in workspace["Tycoons"]:GetChildren() do
					if Tycoon:GetAttribute('Owner') == Dummy:GetAttribute('Owner') then
						DummySpace = Tycoon.Space
					end
				end
				if TempDistance < self.EnemyRange and Distance > TempDistance and DummySpace and not is_a_inside_b(Dummy.HumanoidRootPart, DummySpace) or TempDistance < self.EnemyRange and Distance > TempDistance and not DummySpace then
					Distance = TempDistance
					Enemy = Dummy
				end
			end
		end)
	end
	return Enemy
end

function Controlled:AsFollower()
	self.AsFollower_bool = true
	local clock = os.clock()
	local Connection = RunService.Heartbeat
	Connection = Connection:Connect(function()
		if not self.AsFollower_bool then Connection:Disconnect() return end
		if os.clock()-clock<0.025 then 
			return 
		else
			clock = os.clock()
		end

		if #self.Waypoints>0 then
			if self.Waypoints[self.Index] and self.Waypoints[self.Index].Position and self.Dummy:FindFirstChild('HumanoidRootPart') then
				if (self.Waypoints[self.Index].Position-self.Dummy.HumanoidRootPart.Position).Magnitude<2 then
					self.Index = 1
					self.Destination = nil
					self.Waypoints = {}
					return
				end

				self.Dummy.PrimaryPart:SetNetworkOwner(nil)
				self.Dummy.Humanoid:MoveTo(self.Waypoints[self.Index].Position)
			else
				self.Index = 1
				self.Destination = nil
				self.Waypoints = {}
			end
		end
	end)
end

function Controlled:SetEnemyRange(Number: number)
	self.EnemyRange = Number
end

function Controlled:ResetEnemy()
	self.Enemy = nil
	self.AsEnemy_bool = false
	self:AsEnemy()
end

function Controlled:FollowPart(Part)
	self.AsPartFollower_bool = true
	self:ResetDestination()
	self:SetDestination(Part.Position, Part.CFrame)

	local LastPos = Part.Position
	while self.AsPartFollower_bool do
		if not self.Attacking then
			if (LastPos-Part.Position).Magnitude > 5 then
				self:SetDestination(Part.Position, Part.CFrame*CFrame.new(0,0,5))
			end
		else
			LastPos = Part.Position
		end
		task.wait(0.35)
	end
end

function Controlled:AsEnemy()
	task.spawn(function()
		self.Dummy:SetAttribute('CanAttack', true)
		if not self.EnemyRange then
			self.EnemyRange = AttackTypes[self.Type].Range
		end

		local Clock = os.clock()
		local Path_Review_t = .5

		self.AsEnemy_bool = true
		while self.AsEnemy_bool do
			local Enemy = self.Enemy
			if Enemy and not AIs[Enemy] or not Enemy or Enemy and Enemy:FindFirstChild('Humanoid') and Enemy:FindFirstChild('HumanoidRootPart') and Enemy.Humanoid.Health == 0 then
				repeat 
					self.Enemy = self:GetClosestEnemy()
					task.wait(.1)
				until self.Enemy
			end
			Enemy = self.Enemy

			if Enemy and Enemy:FindFirstChild('HumanoidRootPart') then
				if os.clock()-Clock>Path_Review_t and not self.AsPartFollower_bool then
					Clock = os.clock()
					self:SetDestination(Enemy.HumanoidRootPart.Position, nil, true)
				end
				if (get_xz(Enemy.HumanoidRootPart.Position)-get_xz(self.Dummy.HumanoidRootPart.Position)).Magnitude<AttackTypes[self.Type].Range+(Data.AttackTypes[Enemy:GetAttribute('Type')].Heavy_Range or 0) then
					self.Attacking = true
					self:ResetDestination()
					task.delay(0.1, function()
						pcall(function()
							if self.Dummy and self.Dummy:FindFirstChild('HumanoidRootPart') then
								self.Dummy.HumanoidRootPart.CFrame = CFrame.new(self.Dummy.HumanoidRootPart.Position,Vector3.new(Enemy.HumanoidRootPart.Position.X,self.Dummy.HumanoidRootPart.Position.Y,Enemy.HumanoidRootPart.Position.Z))
							end
						end)
					end)
					AttackTypes[self.Type].Action(AIs[self.Dummy])
				else
					self.Attacking = false
				end
			end
			task.wait(0.05)
		end
		self.Attacking = false
	end)
end

function Controlled:Terminate()
	AIs[self.Dummy] = nil
	self.AsFollower_bool = false
	self.AsEnemy_bool = false
	self.AsPartFollower_bool = false
	self.Dummy:Destroy()
end

return Controlled
