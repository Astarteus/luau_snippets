-- services
local replicated = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
local players = game:GetService("Players")
local text_service = game:GetService("TextService")
local run = game:GetService("RunService")
local marketplace = game:GetService("MarketplaceService")
local datastores = game:GetService("DataStoreService")


-- constants
local sss_modules = sss.modules
local sss_packages = sss.packages
local rs_shared = replicated.shared
local rs_modules = rs_shared.modules
local remotes = replicated.remotes


-- modules
local game_data = require(rs_shared.data)
local utility = require(rs_shared.utility)
local registry = require(rs_shared.registry)
local quests = require(script.quests)
local profile_service = require(sss_packages.ProfileService)
local restaurant_module = require(sss_modules.restaurant)
local replica = require(sss_packages.ReplicaService)
local grid = require(rs_shared.modules.grid)
local a_proximity = require(rs_shared.packages.A_Proximity)
local ro_controlled = require(rs_shared.packages.RoControlled)
local clock_sync = require(rs_shared.packages.ClockSyncHandler)
--clock_sync:Initialize()



-- system...
local system = {}
system.__index = system


-- data tables
local plrs_data = {}
local profile_template = require(script.profile_template)
local profile_store = profile_service.GetProfileStore(
	"PlayerData",
	profile_template
)
local player_token = replica.NewClassToken("PlayerProfile") -- review: each player MAY need a different tokey key (new token for each player)


-- leaderboard 
local leaderboards = {
	["served_customers"] = datastores:GetOrderedDataStore("servedCustomers"),
	["most_rolls"] = datastores:GetOrderedDataStore("mostRolls")
}



local function give_model(plr: Player, model: string)
	local clear_model: string = utility.get_clear_item(model)
	local parent = game_data.WORKERS[clear_model] and "workers" or game_data.MODELS[clear_model] and "inventory"

	local new_inv = plrs_data[plr].replica.Data[parent]
	if new_inv[model] then
		new_inv[model].amount = math.min(game_data.CONSTANTS.max_item_at_once,new_inv[model].amount+1)
	else
		new_inv[model] = {}
		new_inv[model].amount = 1
	end
	plrs_data[plr].replica:SetValue({parent},new_inv)
	
	local new_unlocked_t = plrs_data[plr].replica.Data.unlocked_objects
	table.insert(new_unlocked_t,model)
	plrs_data[plr].replica:SetValue({"unlocked_objects"},new_unlocked_t)
end


system._init_players = function(self)
	players.PlayerAdded:Connect(function(plr)
		-- setting basic attributes
		plr:SetAttribute("last_rolled",0)
		plr:SetAttribute("roll_stack",0)
		plr:SetAttribute("roll_speed_multi",1)
		plr:SetAttribute("luck_multi",1)
		plr:SetAttribute("money_multi",1)
		plr:SetAttribute("walkspeed_multi",1)


		-- creating player data
		plrs_data[plr] = {}

		-- loading player's profile (datastore)
		profile_store:WipeProfileAsync("Player_" .. plr.UserId)
		local profile = profile_store:LoadProfileAsync("Player_" .. plr.UserId)
		if profile then
			profile:AddUserId(plr.UserId)
			profile:Reconcile()
			profile:ListenToRelease(function()
				plrs_data[plr].replica:Destroy()
				plrs_data[plr].profile = nil
				plr:Kick()
			end)
			if plr:IsDescendantOf(players) == true then
				plrs_data[plr].profile = profile
				plrs_data[plr].replica = replica.NewReplica({
					ClassToken = player_token,
					Tags = {Player = plr},
					Data = profile.Data,
					Replication = "All",
				})
			else
				profile:Release()
			end
		else
			plr:Kick("Couldn't load profile, please rejoin!")
		end

		-- setting up the restaurant given player's data
		plrs_data[plr].restaurant = restaurant_module.new(plr, plrs_data[plr].replica)
		plrs_data[plr].quests = quests.new(plr, plrs_data[plr].replica, plrs_data[plr].restaurant)

		plr.CharacterAdded:Connect(function(char)
			-- teleport character to restaurant
			char.HumanoidRootPart.CFrame = plrs_data[plr].restaurant.model.floors.floor_1.Base.CFrame*CFrame.new(0,4,0)

			-- preload anims
			replicated.remotes.effects:FireClient(plr,"animate","preload_anims")

			-- make sure the character's parent is [Alive] folder
			char.Archivable = true
			repeat task.wait() char.Parent=workspace.Alive until char.Parent==workspace.Alive

			task.wait(1)
			remotes.data_act:Fire(plr) -- handles player stuff like unlocked upgrades (and so make the server give boosts) when joined
		end)
		plr:LoadCharacter()
	end)

	players.PlayerRemoving:Connect(function(plr)
		
		-- reset player's restaurant to let others load their data in
		local data_grid = plrs_data[plr].replica.Data.restaurant_grid
		
		for i,int_data in plrs_data[plr].replica.Data.restaurant_grid do
			if typeof(int_data.relative_cframe)=="CFrame" then
				data_grid[i].relative_cframe = utility.pack_cframe(int_data.relative_cframe)
			end
			--if typeof(int_data.look_vect)=="Vector3" then
			--	data_grid[i].look_vect = table.pack(int_data.look_vect.X,int_data.look_vect.Y,int_data.look_vect.Z)
			--end
			--if typeof(int_data.model_size)=="Vector3" then
			--	data_grid[i].model_size = table.pack(int_data.model_size.X,int_data.model_size.Y,int_data.model_size.Z)
			--end
		end
		plrs_data[plr].replica:SetValue({"restaurant_grid"},data_grid)
		
		plrs_data[plr].restaurant:Terminate()

		-- release player's profile
		local profile = plrs_data[plr].profile
		if profile ~= nil then
			profile:Release()
		end

		-- clear player's data
		plrs_data[plr] = nil
	end)
end

system._init_events = function(self)

	-- remote functions
	remotes.ask_placing.OnServerInvoke = function(plr,data)
		return plrs_data[plr].restaurant:Place(data)
	end
	remotes.ask_storing.OnServerInvoke = function(plr,data)
		return plrs_data[plr].restaurant:Store(data)
	end
	remotes.ask_roll.OnServerInvoke = function(plr,data)
		--checks
		local min_len = utility.has_gamepass(plr,game_data.CONSTANTS.gamepasses.fast) and game_data.CONSTANTS.randomizing_len/game_data.CONSTANTS.fast_time_increment or game_data.CONSTANTS.randomizing_len
		if clock_sync:GetTime() - plr:GetAttribute("last_rolled") < min_len then return end
		plr:SetAttribute("last_rolled", clock_sync:GetTime())

		local luck_multi = plr:GetAttribute("luck_multi")
		if plr:GetAttribute("roll_stack") == game_data.CONSTANTS.rolls_req_for_stack then
			plr:SetAttribute("roll_stack",0)
			
			luck_multi *= game_data.CONSTANTS.roll_stack_luck_multiplier
		end

		-- remove decorations since the player already has them
		local reviewed_model_tab = game_data.MODELS
		for name, model in reviewed_model_tab do
			if model.price then reviewed_model_tab[name] = nil end
		end

		-- merge models and workers
		local tab_to_roll = utility.merge(reviewed_model_tab,game_data.WORKERS)
		local rolled_m,rarity = utility.get_rng_item(plr, tab_to_roll, luck_multi)
		
		local vars_array = {[""]={rarity=1}}
		for variant, var_data in utility.dict_merge(game_data.VARIANTS,game_data.VARIANTS_COMBOS) do
			vars_array[`.{variant}`] = var_data
		end
		
		rolled_m = `{rolled_m}{utility.get_rng_item(plr, vars_array, luck_multi)}`
		
		give_model(plr,rolled_m)

		-- set plr's action
		plr:SetAttribute("action",`roll_{rarity}_{os.clock()}`)
		
		-- increase leaderboard value
		remotes.retrieve:Fire(plr,{typ="global",parent="most_rolls",val=1})

		plr:SetAttribute("roll_stack",plr:GetAttribute("roll_stack")+1)
		return rolled_m
	end
	remotes.ask_rename_worker.OnServerInvoke = function(plr,target_id,new_name)
		local success, ft = pcall(function()
			return text_service:FilterStringAsync(new_name,plr.UserId):GetNonChatStringForBroadcastAsync()
		end)
		if (not success) or ft ~= new_name then return end
		if string.len(new_name) > game_data.CONSTANTS.worker_name_characters_limit then return end

		local replica = plrs_data[plr].replica
		for name,adds in replica.Data.equipped_workers do
			if adds.worker_id == target_id then
				local new_tab = replica.Data.equipped_workers
				local new_adds = adds
				new_adds.worker_name = new_name
				new_tab[name] = new_adds
				replica:SetValue({"equipped_workers"},new_tab)
				return true
			end
		end
	end
	remotes.ask_new_slot.OnServerInvoke = function(plr)
		local replica = plrs_data[plr].replica

		local new_slot_i = replica.Data.equipped_workers_capacity+1

		-- check if player has enough money, if so then unlock said worker
		local price = game_data.CONSTANTS.worker_slot_prices[new_slot_i]
		if replica.Data.cash >= price then
			replica:SetValue({"cash"},replica.Data.cash-price)
			replica:SetValue({"equipped_workers_capacity"},new_slot_i)

			return true
		end
	end
	remotes.ask_equip_worker.OnServerInvoke = function(plr,target_type)
		local replica = plrs_data[plr].replica

		-- make sure the player can equip another worker
		if utility.get_dict_len(replica.Data.equipped_workers) >= replica.Data.equipped_workers_capacity then return end

		-- check if there is an available type on the unequipped workers list
		for worker_type,adds in replica.Data.workers do
			if worker_type == target_type then
				-- add worker on the equipped workers table
				local new_dict = replica.Data.equipped_workers

				-- make sure each worker has its own id
				local unique_id
				repeat 
					unique_id = math.random(1,1e5)
				until not utility.get_worker_tab_by_id(replica,unique_id)

				local new_tab = {worker_type=target_type,worker_name=utility.get_random_from_table(registry.worker_names),worker_id=unique_id}
				table.insert(new_dict,new_tab) -- change worker_name to a random name
				replica:SetValue({"equipped_workers"},new_dict)

				local tot_workers_tab = replica.Data.workers
				tot_workers_tab[worker_type].amount -= 1
				if replica.Data.workers[worker_type].amount == 0 then
					tot_workers_tab[worker_type] = nil
				end
				replica:SetValue({"workers"},tot_workers_tab)

				plrs_data[plr].restaurant:_update_workers()
				return new_tab
			end
		end
	end
	remotes.ask_unequip_worker.OnServerInvoke = function(plr,id)
		local success, err = true,nil
		local replica = plrs_data[plr].replica

		for i,data in replica.Data.equipped_workers do
			if data.worker_id == id then
				local target_type = data.worker_type

				local dummy
				for _, temp_dummy in workspace.Dummies:GetChildren() do
					if temp_dummy:GetAttribute("worker_id") == id then
						dummy = temp_dummy; break
					end
				end
				if dummy:GetAttribute("holding_dish") then
					success=false; err="The worker cannot be unequipped when holding a dish!"
					break
				end
			
				-- remove worker on the equipped workers table
				local new_tab = replica.Data.equipped_workers
				for n_i,n_data in new_tab do
					if n_data.worker_id == id then 
						new_tab[n_i] = nil
					end
				end
				replica:SetValue({"equipped_workers"}, new_tab)

				local new_dict = replica.Data.workers
				if not replica.Data.workers[target_type] then
					new_dict[target_type] = {amount=0}
				end
				new_dict[target_type].amount += 1
				replica:SetValue({"workers"},new_dict)

				plrs_data[plr].restaurant:_update_workers()
				return true
			end
		end
		return success, err
	end
	remotes.ask_upgrade.OnServerInvoke = function(plr,upg_name:string)
		local replica = plrs_data[plr].replica

		if replica.Data.upgrades[upg_name] == #game_data.UPGRADES[upg_name].bars then return false, "You cannot upgrade this field more!" end
		local price = game_data.UPGRADES[upg_name].bars[(replica.Data.upgrades[upg_name] and replica.Data.upgrades[upg_name]+1) or 1].price
		if replica.Data.cash < price then return false, "You don't have enough money!" end

		local new_tab = plrs_data[plr].replica.Data.upgrades
		if not new_tab[upg_name] then
			new_tab[upg_name] = 1
		else
			new_tab[upg_name] += 1
		end
		replica:SetValue({"upgrades"},new_tab)
		replica:SetValue({"cash"},replica.Data.cash-price)

		local boost_value = game_data.UPGRADES[upg_name].bars[new_tab[upg_name]].boost_value
		if upg_name == "restaurant_expansion" then
			plrs_data[plr].restaurant:Expand(new_tab[upg_name]+1)
		elseif upg_name == "money_multi" then
			utility.queue_multi(plr,"money_multi",(1+boost_value/100),nil,"exp")
		elseif upg_name == "luck_multi" then
			utility.queue_multi(plr,"luck_multi",(1+boost_value/100),nil,"exp")
		elseif upg_name == "walkspeed_multi" then
			utility.queue_multi(plr,"walkspeed_multi",(1+boost_value/100),nil,"exp")
		end

		return true
	end
	remotes.ask_free_continuous.OnServerInvoke = function(plr,i)
		local success = true
		local replica = plrs_data[plr].replica
		
		local continuous_tab = replica.Data.continuous_data
		for c_i, c_data in continuous_tab do
			if c_i ~= i then continue end
			
			if continuous_tab[i-1] then -- make sure the previous reward has been retrieved
				if not continuous_tab[i-1].purchased then success = false; break end
			end
			if c_data.id == 0 and not c_data.purchased then
				continuous_tab[i]["purchased"] = true
				if c_data.typ == "boost" then 
					remotes.give_item:Fire(plr,c_data.parent)
				else
					remotes.retrieve:Fire(plr,continuous_tab[i])
				end
				
				break
			end
		end
		if success then
			replica:SetValue({"continuous_data"},continuous_tab)
		end
		return success
	end
	remotes.ask_use_item.OnServerInvoke = function(plr,item:string) -- from inventory
		local replica = plrs_data[plr].replica

		local new_inv = replica.Data.inventory
		if not new_inv[item] then return end
		if new_inv[item].amount > 1 then
			new_inv[item].amount -= 1
		else
			new_inv[item] = nil
		end
		replica:SetValue({"inventory"},new_inv)

		local tab = game_data.CONSTANTS.boosts[item]
		if tab then
			local retr_tab = {
				typ = "boost",
				parent = item,
				val = tab.val,
				lasts = tab.lasts,
			}
			remotes.retrieve:Fire(plr,retr_tab)
			return true
		end
	end
	remotes.ask_rest_availability.OnServerInvoke = function(plr,avail:string)
		if avail then -- open
			plrs_data[plr].restaurant:Open()
		else -- close 
			plrs_data[plr].restaurant:Close()
		end
		return true
	end
	remotes.ask_title_change.OnServerInvoke = function(plr,new_title:string)
		local success, result = pcall(function()
			return text_service:FilterStringAsync(new_title,plr.UserId):GetNonChatStringForBroadcastAsync()
		end)
		if success and result then
			if string.find(result,"#") then -- text has been filtered (not allowed)
				return false, "This title cannot be used."
			elseif string.len(result) < game_data.CONSTANTS.min_title_length then
				return false, `The title must contain at least {game_data.CONSTANTS.min_title_length} characters`
			elseif string.len(result) > game_data.CONSTANTS.max_title_length then
				return false, `The title cannot exceed {game_data.CONSTANTS.max_title_length} characters`
			else
				local replica = plrs_data[plr].replica
				replica:SetValue({"restaurant_title"},new_title)
				plrs_data[plr].restaurant.model:SetAttribute("title",new_title)
				return true
			end
		end
	end
	

	-- remote events
	remotes.is_plr_building.OnServerEvent:Connect(function(plr,building)
		plr:SetAttribute("building",building)
	end)


	-- bindables
	remotes.data_act.Event:Connect(function(plr) -- everything that is supposed to affect the player only once when he joins the game
		local replica = plrs_data[plr].replica
 
		-- folders
		local boosts = utility.make_folder({name="boosts",parent=plr})
		local roll_stack_multi = utility.make_folder({name="roll_speed_multi",parent=boosts})
		local money_multi = utility.make_folder({name="money_multi",parent=boosts})
		local luck_multi = utility.make_folder({name="luck_multi",parent=boosts})
		local walkspeed_multi = utility.make_folder({name="walkspeed_multi",parent=boosts})
		
		-- attributes setup
		plr:GetAttributeChangedSignal("walkspeed_multi"):Connect(function()
			local char = plr.Character; if not char then return end 
			char.Humanoid:SetAttribute("WalkSpeed",16*plr:GetAttribute("walkspeed_multi"))
		end)
	
		-- upgrades
		local upgs = replica.Data.upgrades
		for name,upg_i in upgs do
			local boost_value = game_data.UPGRADES[name].bars[upg_i].boost_value
			if name == "restaurant_upgrade" then
				plrs_data[plr].restaurant:Expand(upg_i)
			elseif name == "money_multi" then
				utility.queue_multi(plr,"money_multi",(1+boost_value/100),nil,"exp")
			elseif name == "luck_multi" then
				utility.queue_multi(plr,"luck_multi",(1+boost_value/100),nil,"exp")
			elseif name == "walkspeed_multi" then
				utility.queue_multi(plr,"walkspeed_multi",(1+boost_value/100),nil,"exp")
			end
		end
		
		task.wait(2)
		run.Heartbeat:Connect(function()
			-- shop related
			if DateTime.now().UnixTimestamp - replica.Data.continuous_refreshed_clock > game_data.CONSTANTS.continuous_refresh then
				replica:SetValue({"continuous_refreshed_clock"},DateTime.now().UnixTimestamp)

				local randoms_tab = {}
				local curr_i = 1
				for _,s_data in game_data.CONSTANTS.continuous_structure do

					local to_copy_tab = utility.get_random_from_table(game_data.CONSTANTS.continuous_chances[s_data.category])
					local chosen_tab = utility.clone(to_copy_tab)
					chosen_tab.category=s_data.category;chosen_tab.price=s_data.price;chosen_tab.id=s_data.id
					
					randoms_tab[curr_i] = chosen_tab
					curr_i+=1
					
					if s_data.price ~= 0 then
						local free_counts = math.random(game_data.CONSTANTS.continuous_free_counts[1],game_data.CONSTANTS.continuous_free_counts[2])
						for i = 1, free_counts do
							to_copy_tab = utility.get_random_from_table(game_data.CONSTANTS.continuous_chances[s_data.category])
							local free_tab = utility.clone(to_copy_tab)
							free_tab.category=s_data.category;free_tab.price=0;free_tab.id=0

							randoms_tab[curr_i] = free_tab
							curr_i+=1
						end
					end
				end
				replica:SetValue({"continuous_data"},randoms_tab)
			end
			
			-- boosts
			for _, dep in boosts:GetChildren() do
				local tot_val = 1
				for n,v in dep:GetAttributes() do
					if string.sub(n,n:len()-3,n:len())=="_len" then continue end
					
					local prob_len = dep:GetAttribute(n.."_len")
					if prob_len then 
						if os.clock()-prob_len>0 then
							dep:SetAttribute(n,nil)
							dep:SetAttribute(n.."_len",nil)
							continue
						end
					end
					tot_val*=v
				end
				plr:SetAttribute(dep.Name,tot_val)
			end
		end)
	end)
	remotes.give_item.Event:Connect(function(plr,item:string)
		local replica = plrs_data[plr].replica
		
		local new_inv = replica.Data.inventory
		if new_inv[item] then
			new_inv[item].amount += 1 
		else
			new_inv[item] = {amount = 1}
		end
		replica:SetValue({"inventory"},new_inv)
	end)
	remotes.give_currency.Event:Connect(function(plr,tab: {parent: string, val: number})
		local replica = plrs_data[plr].replica
		local multi
		if tab.parent == "cash" then
			multi = plr:GetAttribute("money_multi")
		end
		if tab.parent == "experience" then
			local curr_lv = utility.get_level_by_experience(replica.Data.experience)
			local next_lv = utility.get_level_by_experience(replica.Data.experience+tab.val)
			if curr_lv ~= next_lv and game_data.CONSTANTS.level_rewards[next_lv] then
				remotes.retrieve:Fire(plr,game_data.CONSTANTS.level_rewards[next_lv])
			end
			if next_lv == game_data.CONSTANTS.max_level then
				return
			end
		end
		local true_val = tab.val*(multi or 1)
		replica:SetValue({tab.parent},replica.Data[tab.parent]+true_val)
	end)
	remotes.retrieve.Event:Connect(function(plr,tab) -- when the player has to receive a boost / currency amount
		local replica = plrs_data[plr].replica
		
		-- set plr's action
		plr:SetAttribute("action",`retrieve_{tab.typ}_{tab.parent}_{tab.val}_{os.clock()}`)
		
		if tab.typ then
			if tab.typ=="currency" then
				remotes.give_currency:Fire(plr,tab)
			elseif tab.typ=="boost" then
				-- check if boost is a potion 
				local potion = game_data.CONSTANTS.boosts[tab.parent]
				if potion then
					utility.queue_multi(plr,potion.parent,potion.val,potion.lasts,"potion")
					remotes.push_new_boost:FireClient(plr,tab.parent)
				else
					utility.queue_multi(plr,tab.parent,tab.val,tab.lasts,"random")
				end
			elseif tab.typ=="global" then
				replica:SetValue({tab.parent},replica.Data[tab.parent]+tab.val)
			end
		end
	end)
end


system._init_server = function()
	
	-- remove studio models
	for _, model in workspace._StudioOnlyModels:GetChildren() do
		model:Destroy()
	end
	
	-- passes/products
	marketplace.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if not purchased then return end
		
		local plr = players:GetPlayerByUserId(userId)
		local replica = plrs_data[plr].replica

		local continuous_data = replica.Data.continuous_data
		for i,c_data in continuous_data do
			if c_data.id == productId then
				local curr_tab = replica.Data.continuous_data
				curr_tab[i].purchased = true
				replica:SetValue({"continuous_data"},curr_tab)
				
				if c_data.typ == "boost" then 
					remotes.give_item:Fire(plr,c_data.parent)
				else
					remotes.retrieve:Fire(plr,c_data)
				end
				break
			end
		end
	end)
	marketplace.PromptGamePassPurchaseFinished:Connect(function(plr, gamepassId, purchased)
		if not purchased then return end

	end)
	
	
	run.Heartbeat:Connect(function()
		replicated.config.server_clock.Value = os.clock()
	end)
end

system._init_leaderboards = function()
	
	task.spawn(function()
		local last_ds = 0
		local last_lb = 0
		
		while task.wait() do
			
			if os.clock() - last_ds > game_data.CONSTANTS.save_lb_datastores_delay then
				last_ds = os.clock()
				for _, player in players:GetChildren() do
					local plrData = plrs_data[player]

					for ds_title, ds in leaderboards do
						pcall(function()
							ds:SetAsync(player.UserId.."_"..ds_title, plrData.replica.Data[ds_title])
							--print(lb_data.ds:GetAsync(player.UserId.."_"..ds_title))
						end)
					end
				end
			end
			if #players:GetChildren() ~= 0 then -- make sure there's at least one player before sending data to the clients
				if os.clock() - last_lb > game_data.CONSTANTS.reset_lb_delay then
					last_lb = os.clock()
					local data_pack = {}
					for ds_title, ds in leaderboards do
						local dsSortedAsync = ds:GetSortedAsync(false, 100, 1)
						--print'printing'
						--print(lb_data.ds:GetSortedAsync(false, 100):GetCurrentPage())
						data_pack[ds_title] = {}
						
						for _, pair in ipairs(dsSortedAsync:GetCurrentPage()) do
							table.insert(data_pack[ds_title], pair)
						end
						if not dsSortedAsync.IsFinished then
							dsSortedAsync:AdvanceToNextPageAsync()
						end
					end
					print(data_pack)
					replicated.remotes.push_leaderboards:FireAllClients(data_pack)
				end
			end
		end
	end)
end

system.new = function()
	local self = {}
	setmetatable(self,system)

	-- init modules
	a_proximity.new()

	-- init functions
	self:_init_server()
	self:_init_players()
	self:_init_events()
	self:_init_leaderboards()

	return self
end

system.GetPlrData = function(plr: Player)
	return plrs_data[plr]
end


return system
