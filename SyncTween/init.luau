--!strict
-- Version 1.0.8

local Modules = script:WaitForChild("Modules")

-- // Sub-modules
local Helper = require(Modules.Helper)
local Signal = require(Modules.Signal)
local Custom = require(Modules.Custom)
local settings = require(Modules.settings)

-------------------------------------------------------------------------------------------------
-- // Imported Types
type CustomImpl = Custom.CustomImpl
type TweenArray = Helper.TweenArray
type TweenSignal = Signal.RBXScriptSignal
type Tweens = TweenInfo | TweenArray | string

-- // Created Types
type Data = { [string]: Sync? }
type Private = { [string]: { scope: { Player }?, n_prop: number? }}

type SyncImpl = {
	__index: SyncImpl,

	-- Contructor
	new: (
		object: Instance, tweenInfo: Tweens?,
		properties: { [string]: any }?, update: boolean?,
		sync: (boolean | number)?, additional: { any }?, uuid: string?, start: number?,
		delta: number?, original: { [string]: any }?
	) -> Sync,

	-- Class Methods
	get: (object: Instance, player: Player?) -> { Sync },

	-- Object Methods
	Play: (self: Sync, players: { Player }?) -> (),
	Pause: (self: Sync, delta: number?) -> (),
	Cancel: (self: Sync) -> (),
}

type self = {
	-- Variables:
	sync: (boolean | number)?, -- Default: False
	additional: { any };
	object: Instance,
	update: boolean?, -- Default: True
	UUID: string,
	tween: Tweens?,

	-- Time:
	start: number?,
	delta: number,

	-- Properties:
	original: { [string]: any },
	properties: { [string]: any }?,

	-- Signals:
	Played: TweenSignal, Paused: TweenSignal,
	Canceled: TweenSignal, Completed: TweenSignal,

	--- Created further on ---
	-- Workers:
	waiter: thread?,
	listener: RBXScriptConnection?,
	connection: RBXScriptConnection?,
	animation: Tween?,

	-- Additional
	temporary: any?,
	--------------------------
}

export type Sync = typeof(
	setmetatable({} :: self, {} :: SyncImpl)
)

type ControllerImpl = {
	__newindex: (array: Data, index: string, value: Sync?) -> (),
}

type Controller = typeof(
	setmetatable({} :: Data, {} :: ControllerImpl)
)

type Controls = {
	amount: number;
	private: Private;	  -- Keeps information about who is playing the animation.
	data: Controller; -- All the sync information
}
-------------------------------------------------------------------------------------------------

local SyncTween: SyncImpl = {} :: SyncImpl
SyncTween.__index = SyncTween

-------------------------------------------------------------------------------------------------

--[[

SyncTween - A rich TweenService replication module.
    Copyright (C) 2024  @creacowo

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
--

This is a tweening library that is designed to help with server-to-client animations.

The library is designed to be as flexible as possible, allowing developers to create custom animations
For more information about this module, please head to https://github.com/CreacOwo/SyncTween

--]]

-------------------------------------------------------------------------------------------------

-- // Required Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- // Required Variables
local getTween: RemoteFunction = script.getTween 	-- Get all the tween information from the server
local signalTween: RemoteEvent = script.signalTween -- Signal the tween information to the client

-- // Cache
local Controllers: { [Instance]: Controls } = {} 	-- A table of all the animations that are currently playing

-------------------------------------------------------------------------------------------------
if RunService:IsServer() then
	setmetatable(Controllers, {
		__newindex = function(array: { [Instance]: { Sync } }, index: Instance, value: Controls)
			rawset(array, index, value)

			if value then index:AddTag(settings.COLLECTION_TAG)
			else index:RemoveTag(settings.COLLECTION_TAG) end
		end
	})
end

-- // Private Methods
local Controller = {
	__newindex = function(array, index, value)
		local self: Sync = value or table.clone(array[index] :: Sync)
		local private = Controllers[self.object].private[self.UUID]
		local updateRelative: boolean = RunService:IsServer() and self.update
			or RunService:IsClient() and not self.update

		rawset(array, index, value)

		if value then
			-- Here, we are adding a new controller to the list of controllers (Playing).
			-------------------------------------------------------------------------------------------------
			if self.properties then
				for property in self.properties do
					-- Pause animations that also modify the same property.
					for _, controller in pairs(array) do
						if not (controller and controller.properties) then continue end
						if controller.UUID == self.UUID then continue end

						local controllerPrivate = Controllers[self.object].private[controller.UUID]
						if controller.properties[property] and controllerPrivate.n_prop then
							-- We will then remove the properties from the array and make sure theres no other properties tweening.
							controllerPrivate.n_prop -= 1

							if controllerPrivate.n_prop <= 0 then
								controller:Pause()
							else
								if updateRelative and controller.tween and typeof(controller.tween) ~= "string" then
									self.original[property] = Helper.getPropertyAtCurrentTime(
										controller.start, controller.delta, controller.tween, 
										controller.original[property], controller.properties[property]
									)
								end

								controller.properties[property] = nil
							end
						end
					end
				end

				if updateRelative or RunService:IsClient() then
					Helper.getAllProperties(self.original, self.object, self.properties)
				end				
			end

			-------------------------------------------------------------------------------------------------
			self.Played:Fire()
			-------------------------------------------------------------------------------------------------
			self.start = self.start or workspace:GetServerTimeNow()

			if RunService:IsServer() then				
				local players: { Player } = private.scope or Players:GetPlayers()

				-- On the server, we take care of distributing the tween to the clients.
				for _, player in players do
					signalTween:FireClient(player, self, true)
				end

				-------------------------------------------------------------------------------------------------
                --[[
                    2 SCENARIOS:
                        1. The animation has no set time. (Other)
                        2. The animation has a set time regardless of synchronization. (stepped/animation)

                    In scenario 1, we will not be able to keep track of when the animation will end.
                    In scenario 2-3, we can use the Helper module to know how long the animation will last.

                    On the server, we use a clock.
                --]]
				-------------------------------------------------------------------------------------------------

				-- 1. No set time (No need to wait).
				if typeof(self.tween) == "string" then
					local Implementation: CustomImpl = Custom[self.tween]
					if Implementation and Implementation.orig then
						self.original = Implementation.orig(self.object, self.original, self.properties, self.additional)
						self.properties = self.original
					end
				elseif self.tween then
					-- 2-3. Set time (Predict end).
					local tweenTime: number = Helper.getFullTweenTime(self.tween)

					if tweenTime > 0 then
						self.waiter = coroutine.create(function()
							local deltaLeft: number = tweenTime - self.delta

							task.wait(deltaLeft)

							self.Completed:Fire()
							self:Pause()
						end)
						if self.waiter then coroutine.resume(self.waiter) end
					end
				end

			else
				-- Variables:
				local Finished: TweenSignal = Signal.new()
				local FPS = typeof(self.sync) == "number" and self.sync or settings.FPS
				local currentDelta: number = (workspace:GetServerTimeNow() - self.start) + self.delta

				-------------------------------------------------------------------------------------------------
                --[[
                    3 SCENARIOS:
                        1. The tween is a string (Custom Animation). (Other)
                        2. The animation needs to be synchronized with the server. (stepped)
                        3. The animation does not need to be synchronized with the server. (animation)

                    On the client, we use a signal.
                --]]
				-------------------------------------------------------------------------------------------------

				-- Listen to the completion of the tween.
				self.listener = Finished:Once(function()
					self.Completed:Fire()
					self:Pause()
				end)

				-- 1. Custom Animation
				if typeof(self.tween) == "string" then
					local Implementation: CustomImpl = Custom[self.tween]
					if Implementation then
						self.temporary = Implementation.run(Finished, self.object, self.original, self.properties, self.additional, self.delta, FPS)
					end
				elseif self.tween then
					if not self.properties then
						Finished:Fire()
						return
					end

					-- 2-3. Synchronized / Unsynchronized Animation
					if self.sync then
						-- The animation needs to be synchronized with the server.

						local clk: number = os.clock()
						local saturated: boolean = false
						self.connection = RunService.RenderStepped:Connect(function()
							if saturated then return end -- Stop if animation has ended
							if not self.object then saturated = true return end -- Stop if object is destroyed

							-- Accumulate delta time and prevent excessive updates
							if os.clock() - clk < 1 / FPS then return end
							currentDelta += (os.clock() - clk)
							clk = os.clock()

							local alpha, overflow = Helper.getAlpha(self.tween, currentDelta)
							saturated = overflow

							Helper.bulkChangePropertyWithAlpha(self.object, self.original, self.properties, alpha)

							-- Fire event if animation saturation is reached
							if saturated then Finished:Fire() end
						end)
					else
						-- The animation does not need to be synchronized with the server.
						local totalTime: number = Helper.getFullTweenTime(self.tween)
						if totalTime > 0 then -- If it's not infinite, account for the delay
							self.tween = Helper.modifyTween(self.tween, "Time", self.tween.Time - currentDelta)
						end

						self.animation = TweenService:Create(self.object, self.tween, self.properties)

						if self.animation then
							self.animation:Play()
							self.connection = self.animation.Completed:Once(function()
								Finished:Fire()
							end)
						end
					end
				else
					-- For no animations
					Finished:Fire()
				end
			end
		else			
			if not self then return end

			-- Here, we are removing the controller from the list of controllers (Pausing).
			-------------------------------------------------------------------------------------------------
			if RunService:IsServer() then
				-- Cleanup:
				if self.waiter and coroutine.status(self.waiter) == "suspended" then
					coroutine.close(self.waiter)
				end
				self.waiter = nil
			else
				-- Cleanup:
				if self.animation then self.animation:Pause() self.animation = nil end
				if self.listener then self.listener:Disconnect() self.listener = nil end
				if self.connection then self.connection:Disconnect() self.connection = nil end

				if typeof(self.tween) == "string" then
					local Implementation: CustomImpl = Custom[self.tween]
					if Implementation and Implementation.clear then
						Implementation.clear(self.temporary)
					end
				end
				self.temporary = nil
				-------------------------------------------------------------------------------------------------
			end

			if RunService:IsServer() then
				local players: { Player } = private.scope or Players:GetPlayers()

				-- On the server, we take care of distributing the tween to the clients.
				for _, player in players do
					signalTween:FireClient(player, self, false)
				end
			end
		end
	end,
} :: ControllerImpl

-------------------------------------------------------------------------------------------------

-- // Private Methods
local function addSync(data: Sync, players: { Player }?)
	local objectControls: Controls = Controllers[data.object]

	if objectControls then
		if objectControls.data[data.UUID] then return end
		objectControls.amount += 1
	else
		objectControls = {
			amount = 1;
			private = {};
			data = setmetatable({} :: { [string]: Sync }, Controller);
		} :: Controls
	end
	objectControls.private[data.UUID] = objectControls.private[data.UUID] or {}

	local private = objectControls.private[data.UUID]
	if players then
		local scope = private.scope

		if scope then
			table.move(players, 1, #players, #scope + 1, scope)
		else
			private.scope = players
		end
	end

	if data.properties then
		private.n_prop = Helper.countProperties(data.properties)
	end

	Controllers[data.object] = objectControls
	objectControls.data[data.UUID] = data
end

local function removeSync(data: Sync)
	local objectControls: Controls = Controllers[data.object]
	if not objectControls then return end

	local metatable: ControllerImpl = getmetatable(objectControls.data)
	metatable.__newindex(
		rawget(objectControls, "data"), data.UUID, nil
	)

	objectControls.amount -= 1
	objectControls.private[data.UUID] = nil

	if objectControls.amount <= 0 then
		Controllers[data.object] = nil -- This will fire the list metatable.
	end
end
--

-------------------------------------------------------------------------------------------------

-- // Constructor
function SyncTween.new(object, tweenInfo, properties, update, sync, additional, uuid, start, delta, original): Sync
	local self = {}

	-- Define:
	self.sync = sync
	self.object = object
	self.additional = additional or {}
	self.update = update ~= nil and update or true
	self.UUID = uuid or HttpService:GenerateGUID(false)

	-- Time:
	self.delta = delta or 0
	self.start = start

	-- Properties:
	self.original = original or {}
	self.properties = properties

	-- Signals:
	self.Played = Signal.new()
	self.Paused = Signal.new()
	self.Canceled = Signal.new()
	self.Completed = Signal.new()

	-- Modifications:
	-------------------------------------------------------------------------------------------------

    --[[
        Unfortunately, ROBLOX does not allow developers to transfer TweenInfos through remotes.
        This means that we have to convert the TweenInfo into a table and then convert it back.
    --]]

	local transformation: unknown
	if tweenInfo then
		if RunService:IsServer() then
			if typeof(tweenInfo) == "TweenInfo" then
				transformation = Helper.tweenToArray(
					(tweenInfo :: TweenInfo)
				)
			end
		else
			if typeof(tweenInfo) == "table" then
				transformation = Helper.arrayToTween(
					(tweenInfo :: { [string]: any })
				)
			end
		end
	end

	self.tween = ((transformation or tweenInfo) :: Tweens?)

	-------------------------------------------------------------------------------------------------

	return setmetatable(self, SyncTween)
end

-- // Public Methods
function SyncTween.get(object: Instance, player: Player?): { Sync }
	if RunService:IsServer() then
		local running: { Sync } = {}

		-- Only return the tweens that are running for the player
		local objectControllers = Controllers[object]
		if objectControllers then
			for instance, sync in pairs(objectControllers.data) do
				if not sync then continue end
				local private = objectControllers.private[sync.UUID]
				local scope = private.scope

				if not player or not scope or table.find(scope, player) then
					table.insert(running, sync)
				end
			end
		end

		return running
	else
		return getTween:InvokeServer(object)
	end
end

-- // Class Methods
function SyncTween:Play(players)
	addSync(self, players)
end

function SyncTween:Pause(delta)
	self.delta = (delta ~= nil and delta) 
		or (workspace:GetServerTimeNow() - self.start + self.delta)
	removeSync(self)

	self.start = nil

	if RunService:IsServer() and not self.update then return end
	local alpha = Helper.getAlpha(self.tween, self.delta)
	Helper.bulkChangePropertyWithAlpha(
		self.object, self.original, self.properties, alpha
	)
end

function SyncTween:Cancel()
	self:Pause(0)
	table.clear(self.original)
end

-------------------------------------------------------------------------------------------------
-- // Connections
if RunService:IsServer() then
	getTween.OnServerInvoke = function(player: Player, object: Instance)
		return SyncTween.get(object, player)
	end
else
	local function handleRequest(data: Sync, creation: boolean)
		if not data.object then return end
		if creation then
			SyncTween.new(data.object, data.tween, data.properties, data.update,
				data.sync, data.additional, data.UUID, data.start, data.delta, data.original
			):Play()
		else
			local objectControllers = Controllers[data.object]
			if not objectControllers then return end

			local Potential: Sync? = objectControllers.data[data.UUID]
			if not Potential then return end

			Potential:Pause(data.delta)
		end
	end

	local function handleCollection(object: Instance, creation: boolean)
		if creation then
			local tweens = SyncTween.get(object)
			for _, data in tweens do
				handleRequest(data, true)
			end
		else
			local objectControllers = Controllers[object]
			if objectControllers then
				for _, self in pairs(objectControllers.data) do
					if not self then continue end
					self:Pause()
				end
			end
		end
	end

	signalTween.OnClientEvent:Connect(function(data: Sync, creation: boolean)
		handleRequest(data, creation)
	end)

	for _, object in CollectionService:GetTagged(settings.COLLECTION_TAG) do
		coroutine.wrap(function()
			handleCollection(object, true)
		end)()
	end

	CollectionService:GetInstanceAddedSignal(settings.COLLECTION_TAG):Connect(function(instance)
		handleCollection(instance, true)
	end)

	CollectionService:GetInstanceRemovedSignal(settings.COLLECTION_TAG):Connect(function(instance)
		handleCollection(instance, false)
	end)
end
-------------------------------------------------------------------------------------------------

return SyncTween