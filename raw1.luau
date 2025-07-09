local unit = {}


-- SERVICES
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")


-- CONSTANTS
local RoControlled = script.Parent.Parent
local main = RoControlled._main
local common = RoControlled._common


-- MODULES
local Settings = require(RoControlled.Settings)
local utility = require(common.utility)
local collision = require(common.collision)
local signal = require(common.signal)
local engage_types = require(script.engage_types)


-- ROUnit...
local Unit = {}
Unit.__index = Unit

export type adds = {
	health: number,
	speed: number,

	custom_anim_directory: Folder?,
	custom_uncollideables: {[any]:Instance}?,
	custom_to_hrp_offset: number?,
}

---------
-- LOCALS
Unit.play_anim = function(self, name: string, adds: {})
	table.insert(self.vars.playing_anims,name)
	utility.get_remote(self.model,"play_anim",true):FireAllClients(name,adds)
end
Unit.stop_anim = function(self, name: string)
	table.remove(self.vars.playing_anims,table.find(self.vars.playing_anims,name))
	utility.get_remote(self.model,"stop_anim",true):FireAllClients(name)
end
Unit.get_engaged = function(self)
	local typ, data = self.vars.engage_type, self.vars.engage_data
	if typ then
		return engage_types[typ](self, data)
	end
end
Unit.push_static_cframe = function(self, val: CFrame)
	self.model:SetAttribute("cframe",val)
	if self.vars.moving_root then self.vars.moving_root.CFrame = val end
	
	self.states:SetAttribute("PlatformStand",true)
end
Unit.remove_static = function(self, val: CFrame)
	self.states:SetAttribute("PlatformStand",false)
end
Unit.push_speed = function(self, val: number) -- pushes CURRENT speed, NOT the data one (walkspeed)
	if self.states:GetAttribute("WalkSpeed") >= val then
		if self.vars.curr_speed==0 and val>0 then
			self.vars.last_move = os.clock()
		end
		self.vars.curr_speed = val
	end
end
Unit.get_py_speed = function(self, dt: number)
	return -(self.vars.curr_speed*dt)
end
Unit.apply_physics = function(self)

	-- consts
	local UPDATE_FREQUENCY = Settings.UPDATE_FREQUENCY
	local DISABLE_FRONT_COLLISIONS = Settings.DISABLE_FRONT_COLLISIONS
	local DISABLE_BODY_MOVERS = Settings.DISABLE_BODY_MOVERS
	local RUN_MIN_SPEED = Settings.RUN_MIN_SPEED
	local JUMP_T = Settings.JUMP_FORCE
	local JUMP_MIN_HEIGHT = Settings.JUMP_MIN_HEIGHT
	local JUMP_MAX_HEIGHT = Settings.JUMP_MAX_HEIGHT
	local JUMP_COOLDOWN = Settings.JUMP_COOLDOWN
	local JUMP_DISTANCE_FROM_WALL = Settings.JUMP_DISTANCE_FROM_WALL
	local FALL_FORCE = Settings.FALL_FORCE
	local SLIDE_FORCE = Settings.SLIDE_FORCE

	-- vars
	local falling = false
	local jumping = false; local jump_clock = 0; local jump_sum = 0
	local force_lerping = false; local lerp_clock = 0;
	local y_ray = nil; local y_ray_clock = 0

	--local last_move_started = 0
	self.vars.curr_speed = self.states:GetAttribute("WalkSpeed")
	self.vars.last_move = 0

	-- collisions
	self.model.HumanoidRootPart.Anchored = true; self.model.HumanoidRootPart.CanCollide=false
	self.collision = collision.new(self,self.model.HumanoidRootPart)

	self.states:SetAttribute("Jump",false)
	self.states:SetAttribute("PhysicalSpeed", self.vars.curr_speed)
	
	local heartbeatClock = os.clock()
	self.connections.physics=runService.Heartbeat:ConnectParallel(function(dt)
		if not self.model or self.states:GetAttribute("PlatformStand") or os.clock()-heartbeatClock<UPDATE_FREQUENCY then return end
		heartbeatClock = os.clock()
		
		local model_cframe = self.vars.cframe
		local model_y_vect = Vector3.new(0,model_cframe.Position.Y,0)
		
		local engaged, target_cframe, pos_to_look = self:get_engaged()
		if engaged then
			target_cframe = engaged
			pos_to_look = utility.get_xz(target_cframe.Position)+model_y_vect
		else
			target_cframe = self.vars.cframe
			pos_to_look = self.vars.cframe.LookVector
		end

		local addon = CFrame.new()
		if target_cframe.Position ~= self.vars.cframe.Position then	
			--if os.clock()-self.vars.last_move>0.3 then
			--print(self.states:GetAttribute("WalkSpeed")*UPDATE_FREQUENCY/0.025)
			self:push_speed(self.states:GetAttribute("WalkSpeed"))
			--end
			addon = CFrame.new(0,0,self:get_py_speed(dt)*UPDATE_FREQUENCY/0.015)
		else
			self:push_speed(0)
			pos_to_look = utility.get_xz(model_cframe.Position+target_cframe.LookVector)+model_y_vect
		end

		-- CALCULATE Y (GRAVITY OFFSET)
		if os.clock()-y_ray_clock > 0.1 then
			y_ray_clock = os.clock()
			y_ray = utility.get_raycast(
				(model_cframe*CFrame.new(0,0,0.25)).Position+Vector3.new(0,5,0),
				Vector3.new(0,-1,0)*150,
				{FilterList=self.vars.uncollideables,FilterType=Enum.RaycastFilterType.Exclude})
		end
		local mag_y_dist = (y_ray.Position.Y+self.vars.to_hrp_size)-model_cframe.Position.Y
		mag_y_dist = utility.convert_sml_n(mag_y_dist) -- convert any small number (1e-4) to 0
		local y_t = math.sqrt(2*math.abs(mag_y_dist)/workspace.Gravity)
		local v = workspace.Gravity*y_t
		local calc_y = 0
		calc_y = math.sign(mag_y_dist)*(300-v)*FALL_FORCE
		local add_mag = math.abs(mag_y_dist)<math.abs(calc_y)
		if add_mag then
			-- MOVING UP
			addon*=CFrame.new(0,mag_y_dist,0)
		else
			-- FALLING
			if mag_y_dist<3 then -- half the hrp size? 
				addon*=CFrame.new(0,calc_y,0)
			end
		end
		if mag_y_dist<0 and not add_mag then falling = true else falling = false end
		if mag_y_dist>=0 and jumping then jumping = false end
		-- IS IT HIGH? then don't move up
		--------------------

		-- CALCULATE FRONT (COLLISIONS)
		local jump_att_condition
		if not DISABLE_FRONT_COLLISIONS then
			local min_front = 1.5; local tot_rays = 6
			local hrp_size = self.vars.sizes["HumanoidRootPart"]
			local front_rays = {}
			for i = 0, tot_rays do
				local ray_origin = (model_cframe*CFrame.new(-hrp_size.X/2+(hrp_size.X/tot_rays*i),0,hrp_size.Z/2)).Position
				local fr_ray = utility.get_raycast(
					ray_origin,
					model_cframe.LookVector*min_front,
					{FilterList=self.vars.uncollideables,FilterType=Enum.RaycastFilterType.Exclude})

				if fr_ray then front_rays[ray_origin]=fr_ray end
			end
			local front_ray,ray_origin = utility.get_most_important_front_ray(model_cframe, front_rays)
			if front_ray then
				local lv = front_ray.Instance.CFrame.LookVector
				local axis = Vector3.new(math.round(math.abs(lv.X)),math.round(math.abs(lv.Y)),math.round(math.abs(lv.Z)))==Vector3.new(0,1,0) and "Z" or "Y"
				local closest_vect = utility.closest_vect_on_part(front_ray.Instance,ray_origin)
				local f_def = (utility.get_xz(closest_vect)-utility.get_xz(ray_origin))
				if f_def.Magnitude<hrp_size.Z*1.5 then
					-- then SLIDE
					if (utility.get_xz(closest_vect)-utility.get_xz(target_cframe.Position)).Magnitude<(utility.get_xz(ray_origin)-utility.get_xz(target_cframe.Position)).Magnitude then
						pos_to_look = utility.get_xz(model_cframe.Position-front_ray.Normal)+model_y_vect
					end
					local dot = utility.get_xz(model_cframe.LookVector):Dot(utility.get_xz((target_cframe.Position-model_cframe.Position).Unit))

					local x_offset = 0
					if math.abs(dot)<1 then
						local side_sign = model_cframe:PointToObjectSpace(target_cframe.Position).X>0 and 1 or -1
						x_offset = SLIDE_FORCE*side_sign*(1-math.abs(dot)^1.5)
					end 
					--local z_offset = 0
					--if utility.get_bounding_box(model_cframe,hrp_size-Vector3.new(0,0,0.2)) then
					--	z_offset+=0.02
					--end
					-- sure z_offset works?^^
					addon*=CFrame.new(x_offset,0,-addon.Position.Z) -- +z_offet
				end
				local highest_y = front_ray.Instance.Position.Y+front_ray.Instance.Size[axis]/2
				local obj_y_dist = highest_y-model_cframe.Position.Y
				if obj_y_dist>JUMP_MIN_HEIGHT and obj_y_dist<JUMP_MAX_HEIGHT and (closest_vect-model_cframe.Position).Magnitude<2 then
					-- then JUMP
					if not jumping and os.clock()-jump_clock>JUMP_COOLDOWN then
						jumping = true; jump_clock = os.clock(); jump_sum = 0; JUMP_T = Settings.JUMP_FORCE*(self.states:GetAttribute("JumpPower")/50)
					end
				end
			end
			jump_att_condition = self.states:GetAttribute("Jump") and not jumping
			if ((jumping) or (jump_att_condition)) and self.states:GetAttribute("JumpPower") ~= 0 then
				if jump_att_condition then
					jumping = true; jump_clock = os.clock(); jump_sum = 0; JUMP_T = Settings.JUMP_FORCE*(self.states:GetAttribute("JumpPower")/50)
				end

				local t = os.clock()-jump_clock
				if t<=JUMP_T then
					local base_front_ray = utility.get_raycast(
						model_cframe.Position+Vector3.new(0,-1.7,0),
						utility.get_xz(model_cframe.LookVector*JUMP_DISTANCE_FROM_WALL),
						{FilterList=self.vars.uncollideables,FilterType=Enum.RaycastFilterType.Exclude})
					local extreme_ray = utility.get_raycast(
						model_cframe.Position,
						model_cframe.LookVector*self.model.HumanoidRootPart.Size.Y/2,
						{FilterList=self.vars.uncollideables,FilterType=Enum.RaycastFilterType.Exclude})
					local tim_dif = JUMP_T/2 - math.min(t,JUMP_T)
					jump_sum = JUMP_T*40*tim_dif^2*math.sign(tim_dif)
					local min_speed = base_front_ray and self:get_py_speed(dt)/7 or self:get_py_speed(dt)/5
					if extreme_ray then min_speed = 0 end
					--if math.abs(mag_y_dist)+jump_sum<0 then
					--	jump_sum*=0
					--end
					addon*=CFrame.new(0,(jump_sum)-calc_y,min_speed)
				else jumping = false
				end
			end
		end

		if not DISABLE_BODY_MOVERS then
			-- Linear Velocity...
			local lv = self.model:FindFirstChildWhichIsA("LinearVelocity",true)
			if lv then
				local is_att_type = lv.RelativeTo == Enum.ActuatorRelativeTo.Attachment0
				local is_max_f_applicable = lv.MaxForce >= 1e5
				local vect_vel = lv.VectorVelocity
				if lv.RelativeTo == Enum.ActuatorRelativeTo.World then
					vect_vel = self.model:GetAttribute("cframe"):VectorToObjectSpace(vect_vel)
				end
				local x = math.sign(vect_vel.X)~=0 and addon.Position.X or 0
				local y = math.sign(vect_vel.Y)~=0 and addon.Position.Y or 0
				local z = math.sign(vect_vel.Z)~=0 and addon.Position.Z or 0
				local sub_v = is_max_f_applicable and addon.Position or Vector3.new(x,y,z)
				addon*=CFrame.new(vect_vel*.015-sub_v)
			end

			-- Body Position...
			local bp = self.model:FindFirstChildWhichIsA("BodyPosition",true)
			if bp then
				if not force_lerping then
					force_lerping = true; lerp_clock = os.clock()
				end
				local lerp_t = os.clock()-lerp_clock
				local max_clock = 1.4*(bp.P/2e4)
				local lerp_pos = model_cframe.Position:Lerp(bp.Position,lerp_t/max_clock)
				local dif = lerp_pos-model_cframe.Position
				addon = CFrame.new(model_cframe:PointToObjectSpace(model_cframe.Position+dif))
			else
				force_lerping = false; lerp_clock = 0
			end
		end

		-- AutoRotate... (NOT YET IMPLEMENTED!!!)
		--if self.states:GetAttribute("AutoRotate") == false then

		--	addon = CFrame.new(CFrame.new(model_cframe.Position, pos_to_look):PointToObjectSpace(addon.Position))
		--else

		--end

		-- END OF CALCULATIONS
		--------------------------
		
		if not DISABLE_FRONT_COLLISIONS then
			addon = self.collision:Adjust(addon) -- Check HRP collisions and avoid entering them
		end
		model_cframe = CFrame.new(model_cframe.Position, pos_to_look) * addon
		
		task.synchronize()


		-- CFrame
		self.vars.cframe = model_cframe
		self.model:SetAttribute("cframe", model_cframe)
		if self.vars.moving_root then self.vars.moving_root.CFrame = self.vars.cframe end

		-- Physical States
		self.states:SetAttribute("PhysicalSpeed", self.vars.curr_speed)

		local is_falling = self.states:GetAttribute("falling")
		self.states:SetAttribute("falling", falling)
		if self.states:GetAttribute("falling") and not is_falling then
			self:play_anim("Fall")
			is_falling = self.states:GetAttribute("falling")
		elseif is_falling and not self.states:GetAttribute("falling") then
			self:stop_anim("Fall")
		end

		local is_jumping = self.states:GetAttribute("jumping")
		self.states:SetAttribute("jumping", jumping)
		if self.states:GetAttribute("jumping") and not is_jumping then
			self:play_anim("Jump")
			is_jumping = self.states:GetAttribute("jumping")
		elseif is_jumping and not self.states:GetAttribute("jumping") then 
			self:stop_anim("Jump")
		end
		if jump_att_condition then self.states:SetAttribute("Jump",false) end

		local is_walking = self.states:GetAttribute("walking")
		self.states:SetAttribute("walking", self.vars.curr_speed>0)
		if self.states:GetAttribute("walking") and not is_walking then
			self:play_anim("Walk"); self:stop_anim("Idle")
			is_walking = self.states:GetAttribute("walking")
		end

		local is_running = self.states:GetAttribute("running")
		self.states:SetAttribute("running", self.vars.curr_speed>=RUN_MIN_SPEED)
		if self.states:GetAttribute("running") and not is_running then
			self:play_anim("Run"); self:stop_anim("Idle")
			is_running = self.states:GetAttribute("running")
		end

		if not is_walking and not self.states:GetAttribute("on_idle") then
			self.states:SetAttribute("on_idle", true)
			self:play_anim("Idle"); self:stop_anim("Run"); self:stop_anim("Walk")
		elseif is_walking then 
			self.states:SetAttribute("on_idle",false)
		end
	end)
end

----------
-- GLOBALS
Unit.Engage = function(self, typ: string, ...)
	self.vars.engage_type = typ
	self.vars.engage_data = ...

	-- clean connections
	local temp_completed = self.vars.engage_locals.Completed
	if temp_completed then
		for _, conn in temp_completed._Connections do
			pcall(function()
				conn:Disconnect()
			end)
		end
	end

	self.vars.engage_locals = {
		Completed = signal.new()
	}
	
	return self.vars.engage_locals
end
Unit.Disengage = function(self)
	self.vars.engage_type = nil
	self.vars.engage_data = nil
	
	local temp_completed = self.vars.engage_locals.Completed
	if temp_completed then
		for _, conn in temp_completed._Connections do
			pcall(function()
				conn:Disconnect()
			end)
			conn = nil
		end
	end

	self.vars.engage_locals = {}
end

Unit.Make = function(model, adds: adds)

	local self = {model=model,adds=(adds or{}),connections={},vars={}}
	setmetatable(self, Unit)

	local prob_hum = model:FindFirstChildOfClass("Humanoid")

	self.vars.cframe = model.HumanoidRootPart.CFrame

	-- size related: 
	self.vars.sizes = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") or p:IsA("MeshPart") then
			self.vars.sizes[p.Name]=p.Size
		end
	end
	local siz = 0
	if model:FindFirstChild("Left Leg") then
		siz = model["Left Leg"].Size.Y
	elseif model:FindFirstChild("LeftUpperLeg") then
		siz = model["LeftUpperLeg"].Size.Y+model["LeftLowerLeg"].Size.Y+model["LeftFoot"].Size.Y
	end
	self.vars.to_hrp_size = self.adds.custom_to_hrp_offset or model.HumanoidRootPart.Size.Y/2+siz-.7

	-- random:
	self.vars.engage_locals = {}
	self.vars.playing_anims = {}
	self.vars.uncollideables = self.adds.custom_uncollideables


	local states = Instance.new("Folder")
	states.Name = "Humanoid"; states.Parent = model
	-- common
	states:SetAttribute("MaxHealth", (self.adds.health) or (prob_hum and prob_hum.MaxHealth) or 100)
	states:SetAttribute("Health", (self.adds.health) or (prob_hum and prob_hum.MaxHealth) or 100)
	states:SetAttribute("WalkSpeed", (self.adds.speed) or (prob_hum and prob_hum.WalkSpeed) or 8)
	states:SetAttribute("JumpPower", 50)
	states:SetAttribute("PlatformStand", false)
	states:SetAttribute("AutoRotate", true)
	self.states = states

	-- outside
	model:SetAttribute("id",utility.get_unique_id_from_folder(Settings.MODEL_PARENT))
	model:SetAttribute("cframe", self.vars.cframe)
	model:SetAttribute("destroying", false)

	if Settings.ADD_MOVING_ROOT then
		self.vars.moving_root = utility.make_inv_part(model,"moving_root")
		self.vars.moving_root.Size = Vector3.new(4,4.5,1.5)
		self.vars.moving_root.Position = Vector3.new(0,-math.abs(model:GetPivot().Position.Y-self.vars.moving_root.Position.Y),0)
		local att=Instance.new("Attachment");att.Parent=self.vars.moving_root
	end

	-- animations
	utility.make_remote(model,"play_anim")
	utility.make_remote(model,"stop_anim")

	if self.adds.custom_anim_directory then
		utility.make_obj(model,self.adds.custom_anim_directory,"custom_anim_directory")
	end

	-- substituting humanoid which is now useless
	if prob_hum then prob_hum:Destroy() end
	-- adding animator instead of humanoid
	local animator =  model:FindFirstChildOfClass("AnimationController")
	if not animator then
		animator = utility.make_anim_controller(model)
	end

	local anim_obj = utility.make_obj(model,animator,"Animator")

	-- applying character physics
	self:apply_physics()

	model:GetAttributeChangedSignal("cframe"):Connect(function()
		if not self or not self.vars then return end
		self.vars.cframe = model:GetAttribute("cframe")
	end)

	model:GetAttributeChangedSignal("destroying"):Connect(function()
		self:Terminate()
	end)

	states:GetAttributeChangedSignal("Health"):Connect(function()
		local val = states:GetAttribute("Health")
		if val <= 0 then 
			model:SetAttribute("destroying",true)
		end
	end)
	
	if Settings.DISABLE_COLLISIONS then
		for _, c in model:GetDescendants() do
			if c:IsA("BasePart") or c:IsA("MeshPart") then
				c.CanCollide = false
			end
		end
	end

	return self
end

Unit.Terminate = function(self, t: number)
	local function act()
		pcall(function()
			self.model:Destroy()
		end)
		if self.connections then for _, conn in self.connections do conn:Disconnect() end end
		self.vars = nil; self.adds = nil; self.connections = nil; self.states = nil; self.model = nil
		self.collision = nil
		self = nil
	end
	if t then
		task.delay(t,function()
			act()
		end)
	else
		act()
	end
end

return Unit
