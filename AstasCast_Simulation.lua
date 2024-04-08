-- This module is the most important one of what I have called "AstasCast" because it follows the same logic of "FastCast". It requires some other modules that I'm not going to publish.
-- It is a project I started and finished some months ago.
-- You may be wondering: "Why not just use FastCast instead of wasting time?". Well the answer is that I wanted to make my own projectile module and learn new things at the same time. That's exactly what I have successfully accomplished.

-- It's quite late for me so I'm not going to explain how it works this time but here's an example where I used it some time ago. Open "AstasCast_Example.lua" to see it.
-- RESULT: https://gyazo.com/1d5f24565f73c00f7ae4e95bcf413903

local Simulation = {}
Simulation.__index = Simulation

-- # SERVICES
local CollectionService = game:GetService('CollectionService')
local RunService = game:GetService('RunService')
local Debris = game:GetService('Debris')

-- # MODULES
local Signal = require(script.Parent.Signal)
local Types = require(script.Parent.Types)

local function GetPositionGivenTime(s0: Vector3, v0: Vector3, t: number, a: Vector3)
	local accelForce = Vector3.new((a.X* t^2)/2, (a.Y* t^2)/2, (a.Z* t^2)/2)
	return s0 + (v0*t) + accelForce
end

local function CastRay(origin: Vector3, direction: Vector3, params: RaycastParams): {}
	local Raycast = workspace:Raycast(origin, direction, params)
	if Raycast then
		local Hit: Types.RayHit = {
			instance = Raycast.Instance,
			position = Raycast.Position,
			normal = Raycast.Normal,
			distance = Raycast.Distance
		}

		return {true, Hit}
	end
	return {false}
end

local function InitRay(origin: Vector3, target: Vector3, length: number, Params: RaycastParams): {[any]: Types.RayHit}
	local RayHits = {}
	local RayParams = Params
	local FilterDescedants = Params.FilterDescendantsInstances

	while true do 
		local HitInfo = CastRay(origin, (target - origin), RayParams)
		if HitInfo[1] and not RayHits[HitInfo[2]] then 
			RayHits[#RayHits+1] = HitInfo[2] 

			if RayParams.FilterType == Enum.RaycastFilterType.Exclude then
				table.insert(FilterDescedants, HitInfo[2].instance)
			else
				table.remove(FilterDescedants, table.find(FilterDescedants, HitInfo[2].instance))
			end 

			RayParams.FilterDescendantsInstances = FilterDescedants
		else 
			break
		end
	end

	return RayHits
end

local function InitSegment(origin: Vector3, target: Vector3, length: number, show: boolean): Types.Trajectory
	local revisedLength = (target - origin).Magnitude
	
	if show then
		local adornment = Instance.new("ConeHandleAdornment")
		adornment.Adornee = workspace.Terrain
		adornment.CFrame = CFrame.new(origin:Lerp(target, 0.5), target)
		adornment.Height = revisedLength
		adornment.Color3 = Color3.new()
		adornment.Radius = 0.25
		adornment.Transparency = 0.5
		adornment.Parent = workspace.Terrain
	end
	
	return {
		origin = origin,
		target = target,
		timeSpent = tick(),
		timeOfMotion = 0, 
		revisedLength = revisedLength,
		castChecked = false
	}
end



function Simulation:Cast(AstasCast, origin: Vector3, direction: Vector3, velocity: number, acceleration: Vector3, motion: Types.Motion)
	local CastData: Types.CastData = AstasCast:GetCastData()
	local DataParams = CastData.RayParams
	local length = CastData.SegmentLength

	local Params = RaycastParams.new()
	Params.FilterType = DataParams.FilterType
	Params.FilterDescendantsInstances = DataParams.FilterDescendants
	Params.IgnoreWater = DataParams.IgnoreWater or false
	Params.RespectCanCollide = DataParams.RespectCanCollide or false

	local Bullet = motion.Bullet or nil
	if Bullet and CastData.CustomBulletFeatures and CastData.CustomBulletFeatures.Attributes then
		for Name, Value in CastData.CustomBulletFeatures.Attributes do
			Bullet:SetAttribute(Name, Value)
		end
	end
	
	if Bullet and CastData.CustomBulletFeatures and CastData.CustomBulletFeatures.Tags then
		for _, Value in CastData.CustomBulletFeatures.Tags do
			CollectionService:AddTag(Bullet, Value)
		end
	end

	local CastSetup = {
		Info = {
			IsPlacingSegments = false,
			SegmentsPlaced = false,
			Paused = false,
			FrameConnection = nil,

			Motion = motion,

			Bullet = Bullet or nil,
			BulletDestructionDelay = CastData.CustomBulletFeatures and CastData.CustomBulletFeatures.DestructionDelay or 0,
		},

		Details = {
			startTime = tick(),
			totalTime = 0,
			currentDistance = 0,
			timeToResume = 0,
			checkedTrajectories = 1,
		},

		Simulation = {
			Trajectories = {},
			RayHits = {},
		},


		Moved = motion.Moved,
		Hit = motion.Hit,
		Ended = motion.Ended,
	}

	local Trajectories: {[any]: Types.Trajectory} = CastSetup.Simulation.Trajectories
	local RayHits: {[any]: Types.RayHit} = CastSetup.Simulation.RayHits

	setmetatable(CastSetup, Simulation)

	local function CanRaycast(): boolean
		if #RayHits == DataParams.MaxHits then
			return false
		end
		return true
	end

	local function CreateFullSegment(revisedLength: number)
		local startPoint = #Trajectories == 0 and origin or Trajectories[#Trajectories].target
		local endPoint = GetPositionGivenTime(origin, direction * velocity, (length / velocity)*(#Trajectories == 0 and 1 or #Trajectories), acceleration)
		--print(endPoint)
		
		-- Create new segment
		local Segment = InitSegment(startPoint, endPoint, revisedLength, CastData.ViewTrajectory)
		Segment.timeOfMotion = CastSetup.Details.totalTime + (revisedLength/velocity)

		Trajectories[#Trajectories+1] = Segment

		CastSetup.Details.totalTime += (revisedLength/velocity)
	end

	local ConnectionType = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

	CastSetup.Info.FrameConnection = ConnectionType:Connect(function()
		if CastSetup.Details.currentDistance >= CastData.MaxDistance then CastSetup:Terminate() return end
		--print('NEW CONNECTION -----------')

		if CastSetup.Info.SegmentsPlaced and not CastSetup.Info.Paused then
			local currentPosition = GetPositionGivenTime(origin, direction * velocity, tick() - CastSetup.Details.startTime, acceleration)
			if Bullet then Bullet.Position = currentPosition end

			CastSetup.Info.Motion.Moved:Fire(currentPosition)

			local currentSegment
			local currentT = tick()
			--print(CastSetup.Details.checkedTrajectories, #Trajectories)
			for i = CastSetup.Details.checkedTrajectories+1, #Trajectories do
				local Trajectory = Trajectories[i]

				if Trajectory.castChecked then 
					continue 
				end
				CastSetup.Details.checkedTrajectories += 1
			    --print(CastSetup.Details.currentDistance)
				
				--print(Trajectories[i-1].timeOfMotion, currentT - CastSetup.Details.startTime, Trajectory.timeOfMotion)
				
				if i == 1 then
					if currentT - CastSetup.Details.startTime < Trajectory.timeOfMotion then
						currentSegment = Trajectory
						break
					end
				else
					if currentT - CastSetup.Details.startTime < Trajectory.timeOfMotion and currentT - CastSetup.Details.startTime >= Trajectories[i-1].timeOfMotion then
						Trajectory.castChecked = true
						currentSegment = Trajectory
						break
					end
				end

				-- Is there any laggy trajectory?
				if not Trajectory.castChecked then
					Trajectory.castChecked = true

					local segmentHits = CanRaycast() and InitRay(Trajectory.origin, Trajectory.target, Trajectory.revisedLength, Params) or {}

					for _, segmentHit in segmentHits do
						RayHits[#RayHits+1] = segmentHit
						CastSetup.Info.Motion.Hit:Fire(segmentHit)
					end
				end
				--break
			end
			CastSetup.Details.currentDistance = (currentPosition - origin).Magnitude

			if currentSegment then
				local segmentHits = CanRaycast() and InitRay(currentSegment.origin, currentSegment.target, currentSegment.revisedLength, Params) or {}

				for _, segmentHit in segmentHits do
					RayHits[#RayHits+1] = segmentHit
					CastSetup.Info.Motion.Hit:Fire(segmentHit)
				end
			end
		elseif not CastSetup.Info.SegmentsPlaced then
			if CastSetup.Info.IsPlacingSegments then
				warn('Frame took too much time to create segments. Consider changing the segment size!')
				CastSetup:Terminate()
				return
			end
			CastSetup.Info.IsPlacingSegments = true

			local division = CastData.MaxDistance / length
			local nOfSegments = math.floor(division)
			local extraSegmentLength = length / 100 * (division - nOfSegments)

			for i = 1, nOfSegments + (extraSegmentLength ~= 0 and 1 or 0) do
				local segmentLength = i~=nOfSegments+1 and length or extraSegmentLength

				CreateFullSegment(segmentLength)
			end

			CastSetup.Info.SegmentsPlaced = true
		end
	end)

	return CastSetup
end

function Simulation:GetState()
	if self.Info.Paused then 
		return 'Paused'
	elseif not self.Info.FrameConnection then
		return 'Ended'
	elseif self.Info.FrameConnection and not self.Info.Paused then
		return 'Running'
	end
end

function Simulation:Pause()
	self.Details.timeToResume = tick() - self.Details.startTime
	self.Info.Paused = true
end

function Simulation:Resume()
	self.Details.startTime = tick() - self.Details.timeToResume
	self.Info.Paused = false
end

function Simulation:Terminate()
	self.Info.FrameConnection:Disconnect()
	self.Info.FrameConnection = nil

	self.Info.Motion.Ended:Fire(self.Simulation.RayHits)

	if self.Info.Bullet then
		Debris:AddItem(self.Info.Bullet, self.Info.BulletDestructionDelay)
	end

	self.Info = nil
	self.Details = nil
	self.Simulation = nil

	setmetatable(self, nil)
end

return Simulation
