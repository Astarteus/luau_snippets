local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Janitor = require(Packages.janitor)
local Zone = require(Packages.zoneplus)

local ServerPackages = ServerScriptService.ServerPackages
local Datastore = require(ServerPackages.datastore2)

local Shared = ReplicatedStorage.Shared
local Utils = require(Shared.Utils)
local Data = require(Shared.Data)

local PlaneService = require(script.Parent.PlaneService)


-- BaseService
local BaseService = {}
BaseService.__index = BaseService

-- locals
local function GetAvailablePlot()
	local Plots = workspace.Bases
	for _, Plot in Plots:GetChildren() do
		if not Plot:GetAttribute("Owner") then
			return Plot
		end
	end
end

----
BaseService.onSpawn = function(self)
	-- Creating the model
	local Model = self.Model

	-- Welding everything
	--for _, Part in Model:GetDescendants() do
	--	if Part == Model.Root then
	--		continue
	--	end
	--	if Part:IsA("BasePart") or Part:IsA("MeshPart") or Part:IsA("UnionOperator") then
	--		Part.Anchored = false
	--		local Weld = Utils.makeRigidWeld(Model.Root, Part)
	--		Weld.C1 = Part.CFrame:ToObjectSpace(Model.Root.CFrame)
	--	end
	--end

	-- Setting properties
	Model.Name = self.Owner.Name
	--Model.Root.CFrame = self.Plot.CFrame
	--Model.Parent = workspace.Bases
	Model:SetAttribute("Owner", self.Owner.Name)

	-- Parts initialization
	for _, Wall in Model.CollisionWalls:GetChildren() do
		Wall.CanCollide = false
	end
	
	-- Signs
	Model.Decors.Sign.sign.Physical.Frame.TextLabel.Text = `{self.Owner.Name}'s Hangar`
end

BaseService.handleRevenues = function(self)
	for _, Slot in self.Model.Slots:GetChildren() do
		Slot.Collect.CanQuery = true
		Slot.Collect.CanTouch = true
	end

	task.spawn(function()
		while self and self.Model and self.Model:FindFirstChild("Slots") do
			for _, Slot in self.Model.Slots:GetChildren() do
				
				-- plane revenue
				local OccupyingPlane = Slot:FindFirstChild("OccupyingPlane")
				if OccupyingPlane and OccupyingPlane.Value then
					if OccupyingPlane.Value:GetAttribute("action") ~= "base_idle" then
						Slot:SetAttribute("revenue", nil)
						continue
					end

					local planeTable = Data.PLANES[OccupyingPlane.Value:GetAttribute("Type")]
					Slot:SetAttribute("revenue", (Slot:GetAttribute("revenue") or 0) + planeTable.revenue)
				else
					Slot:SetAttribute("revenue", nil)
					continue
				end
			end

			task.wait(1)
		end
	end)
end

BaseService.handleLock = function(self)
	-- Free lock
	local FreeRoot = self.Model.LockFree:FindFirstChild("Root")
	local PremiumRoot = self.Model.LockPremium:FindFirstChild("Root")

	local _free = Utils.makeValue({ typ = "Number", value = os.clock()+self.stores._freeStore:Get(0), parent = self.Model, name = "_freeLock" })
	local _premium = Utils.makeValue({ typ = "Number", value = os.clock()+self.stores._premiumStore:Get(0), parent = self.Model, name = "_premiumLock" })

	for _, Root in {FreeRoot, PremiumRoot} do

		Root.Touched:Connect(function(HitPart)
			if (Root:GetAttribute("lastEnabled") or math.huge) <= 0.5 then -- cooldown
				return
			end
			if not HitPart:IsDescendantOf(self.Owner.Character) then -- make sure it's the owner
				return
			end

			Root:SetAttribute("lastActivated", os.clock())

			if Root == FreeRoot then
				if _premium.Value < os.clock() then
					self:AddLock(true)
				end
			else
				-- prompt product
				MarketplaceService:PromptProductPurchase(self.Owner, Data.MARKET.PRODUCTS.premium_lock)
			end
		end)
	end
end

BaseService.heartbeat = function(self)

	local Space = self.Model.Space
	
	local lastDatastoreUpdate = 0

	self._janitor:Add(RunService.Heartbeat:Connect(function()

		local clock = os.clock()

		-- checking if the Base has to be locked/unlocked
		local askLock = false
		if (self.Model._freeLock.Value > clock) or (self.Model._premiumLock.Value > clock) then
			askLock = true
		end
		self.Model:SetAttribute("Locked", askLock)

		-- save locks
		if clock - lastDatastoreUpdate > 0.5 then
			lastDatastoreUpdate = os.clock()
			self.stores._freeStore:Set(self.Model._freeLock.Value-clock)
			self.stores._premiumStore:Set(self.Model._premiumLock.Value-clock)
		end

		
		-- handle incoming stealed planes
		local StealingPlaneObj = self.Owner:FindFirstChild("StealingPlane")
		if StealingPlaneObj and self.Owner.Character then
			local Root = self.Owner.Character.HumanoidRootPart
			
			-- check if the character root is within the base
			if Utils.is_in_bounds(
				Vector2.new(Space.Position.X,Space.Position.Z)-Vector2.new(Space.Size.X/2,Space.Size.Z/2), 
				Vector2.new(Space.Size.X,Space.Size.Z),
				Vector2.new(Root.Position.X,Root.Position.Z)
				) then
			
				local Plane = StealingPlaneObj.Value
				if Plane then -- did the owner steal any plane? 
					-- then give him the stolen plane
					
					-- destroy owner stealing object
					StealingPlaneObj:Destroy()
					
					local typ, oldPlaneId, oldOwner = Plane:GetAttribute("Type"), Plane.Name, Plane:GetAttribute("originalOwner")
					
					-- destroy the previous owner plane
					Plane:Destroy()
					-- remove the plane from the previous owner
					if Players[oldOwner] then
						local Planes = Datastore("Planes"..Data.CONSTANTS.DATA_VERSION, Players[oldOwner])
						local tab = Planes:GetTable({})
						if tab[oldPlaneId] then
							tab[oldPlaneId] = nil
						end
						Planes:Set(tab)
					end
					
					-- create a new plane 
					local newSlot = Utils.GetAvailableSlot(self.Owner)
					local slotName = string.gsub(newSlot.Name,"Slot","")
					local Model = PlaneService.LoadPlane(typ, { Owner = self.Owner, slot = tonumber(slotName) })
					Utils.BoostData(self.Owner, {
						typ = "dict",
						parent = "Planes",
						val = { i = Model.Name, v = { name = typ, slot = tonumber(slotName) } },
					})
				end
			end
		end
	end))
end

-- Globals
BaseService.Create = function(Player: Player)
	local self = setmetatable({
		_janitor = Janitor.new(),
		stores = {
			_freeStore = Datastore("_freeLock"..Data.CONSTANTS.DATA_VERSION,Player),
			_premiumStore = Datastore("_premiumLock"..Data.CONSTANTS.DATA_VERSION,Player),
		}
	}, BaseService)

	self.Owner = Player

	self.Model = GetAvailablePlot()
	self:onSpawn() -- create the model

	self:handleRevenues()
	self:handleLock()

	self:heartbeat()
	

	return self
end

BaseService.Reset = function(self)
	self._janitor:Destroy()
	
	self.Model.Planes:ClearAllChildren()
	
	self.Model:SetAttribute("Owner", nil)
	self.Model:SetAttribute("Locked", nil)
	self.Model:SetAttribute("_lastFreeLock", nil)
	
	Utils.deleteObjectIfExisting(self.Model, "_freeLock")
	Utils.deleteObjectIfExisting(self.Model, "_premiumLock")
	
	for _, Slot in self.Model.Slots:GetChildren() do
		Slot:SetAttribute("revenue", nil)
	end

	self.Model.Decors.Sign.sign.Physical.Frame.TextLabel.Text = ""

	self = nil
end

BaseService.AddLock = function(self, isFree: string)
	-- implies that the payment of the product (if isFree == false) is already made

	if (self.Model:SetAttribute("_lastFreeLock") or math.huge) < (isFree and Data.CONSTANTS.BASE_FREE_LOCK_LENGTH or 0) then
		return
	end
	if isFree and self.Model._freeLock.Value > os.clock() then
		return 
	end

	local adding = os.clock() + (isFree and Data.CONSTANTS.BASE_FREE_LOCK_LENGTH or Data.CONSTANTS.BASE_PREMIUM_LOCK_LENGTH)
	local name = isFree and "_freeLock" or "_premiumLock"

	local timerObject = self.Model:FindFirstChild(name)

	if timerObject.Value < adding then
		timerObject.Value = adding
	end
end

return BaseService
