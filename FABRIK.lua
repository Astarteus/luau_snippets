-- FABRIK stands for "Forward And Back Reaching Inverse Kinematics"
-- This came to my mind when I wanted to simulate the movements of a spider 

-- PROCESS:
-- 1. You start by filling your variable with a new chain by doing .MakeChain() given x parts, y destination vector, and the number of epochs (the more epochs, the higher the precision. default = 5).
-- 2. After the first step you are gonna use the most useful chain method that is :Move() which only requires the goal position

local FABRIK = {}
FABRIK.__index = FABRIK

local RunService = game:GetService('RunService')

local function MakePart()
	local Part = Instance.new('Part')
	Part.Anchored = true; Part.CanCollide = false; Part.CanQuery = false
	Part.Material = Enum.Material.Glass
	Part.Parent = workspace
	return Part
end

function FABRIK:Forwards()
	for i=1,#self.points do
		local p_i = i
		local p = self.points[p_i]
		if i==1 then
			self.points[p_i] = self.start
			continue
		end
		local lp_i = i-1
		local lp = self.points[lp_i]
		self.points[p_i]=lp-(lp-p).Unit*self.lengths[lp_i]
	end
end

function FABRIK:Backwards()
	for i=0,#self.points-1 do
		local p_i =#self.points-i
		local p = self.points[p_i]
		if i==0 then
			self.points[p_i] = self.goal
			continue
		end
		local hp_i = p_i+1
		local hp = self.points[hp_i]
		self.points[p_i]=hp-(hp-p).Unit*self.lengths[p_i]
	end
end

function FABRIK.MakeChain(parts, goal: Vector3, epochs: number?)
	local self = {}
	setmetatable(self, FABRIK)
	self.parts = parts
	self.points = {}
	for i, part in parts do
		self.points[i] = part.Position
	end
	self.start = self.points[1]
	self.goal = goal
	self.target_distance = (goal-self.start).Magnitude
	self.epochs = epochs or 5
	self.points_length = 0
	self.lengths = {}
	self.moving = false
	for i, point in self.points do
		if i>1 then
			self.points_length+=(point-self.points[i-1]).Magnitude
		end
		if i~=#self.points then
			self.lengths[i] = (self.points[i+1]-self.points[i]).Magnitude
		end
	end
	self.beams = {}
	for i = 1, #self.points-1 do
		local p = MakePart()
		p.CFrame = CFrame.new(self.points[i]:Lerp(self.points[i+1], 0.5), self.points[i+1])
		p.Size = Vector3.new(0.5,0.5,(self.points[i]-self.points[i+1]).Magnitude)
		self.beams[i] = p
	end
	warn('Chain created!')
	return self
end

function FABRIK:Move(goal: Vector3?)
	for i, part in self.parts do
		self.points[i] = part.Position
	end
	self.start = self.points[1]
	if goal then
		self.goal = goal
		self.target_distance = (goal-self.start).Magnitude
	end
	self.moving = true
	for i = 1,self.epochs do
		self:Backwards()
		if RunService:IsClient() then
			RunService.RenderStepped:Wait() 
		else
			RunService.Heartbeat:Wait()
		end
		self:Forwards()
	end
	self.moving = false
	for i, part in self.parts do
		if i==1 then continue end
		part.Position = self.points[i]
	end
	for i, beam in self.beams do
		beam.CFrame = CFrame.new(self.points[i]:Lerp(self.points[i+1], 0.5), self.points[i+1])
	end
end

return FABRIK
