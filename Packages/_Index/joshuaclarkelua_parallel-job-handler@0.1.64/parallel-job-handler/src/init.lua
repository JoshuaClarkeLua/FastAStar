local HttpService = game:GetService("HttpService")
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local Promise = require(script.Parent.Promise)
local Signal = require(script.Parent.Signal)

local DEFAULT_NUM_ACTORS = 64
local handlers = {} :: {[string]: JobHandler}

--[=[
	@class Topic

	Used internally to communicate with the job handler when hooking new topics
	or returning data from a topic execution in a job script.
]=]
local Topic = {}
Topic.__index = Topic

--[=[
	@function new
	@within Topic
	@private
	@ignore

	Creates a new topic.

	@param jobActor ParallelJobActor -- The job actor
	@param topic string -- The topic name
	@return Topic -- The topic
]=]
function Topic.new(jobActor: ParallelJobActor, topic: string): Topic
	if jobActor._started then
		error(`Cannot create new topics after job has started!`)
	end
	jobActor._OnNewTopicSignal:Fire(topic)
	local self = setmetatable({
		_jobActor = jobActor,
		_topic = topic,
	}, Topic)
	return self
end

--[=[
	@function Return
	@within Topic

	Returns data to the job and passes the return values as 
	arguments to the topic handler of the current topic.

	@param ... any -- Data to return
]=]
function Topic:Return(...: any): ()
	self._jobActor:_OnTaskFinished(self._topic, ...)
end

export type Topic = typeof(Topic.new(...)) & {
	-- functions
	new: (jobActor: ParallelJobActor, topic: string) -> Topic;
	-- methods
	Return: (self: Topic, ...any) -> ();
}

--[=[
	@class ParallelJobActor

	Used to bind to messages on the actor that the job script is running on.
	Automatically communicates with the Job.

	IMPORTANT: Bind all messages immediately after calling Job.getActor()
]=]
local ParallelJobActor = {}
ParallelJobActor.__index = ParallelJobActor

--[=[
	@function getScript
	@within ParallelJobActor
	@private
	@ignore

	Returns the script currently executing a task.

	@return Script -- The script
]=]
local function getScript(): Script
	return getfenv(0).script
end

--[=[
	@function new
	@within ParallelJobActor
	@private
	@ignore

	Creates a new job actor used in Job scripts.

	@return ParallelJobActor -- The job actor
]=]
function ParallelJobActor.new(): ParallelJobActor
	local script = getScript()
	local actor: Actor = script:GetActor()
	if actor.Parent == nil then
		error(`Job script is not parented to an Actor!`)
	end
	local self = setmetatable({
		_handlerId = script.Name,
		_actor = actor,
		_started = false,
	}, ParallelJobActor)
	self:_Init()
	return self
end

--[=[
	@method _Init
	@within ParallelJobActor
	@private
	@ignore

	Initializes job actor used in Job scripts.

	@param actor Actor -- The actor to initialize
]=]
function ParallelJobActor:_Init()
	local actor = self._actor
	local thread = coroutine.running()
	local OnActorReady: BindableEvent
	actor:BindToMessage(
		self._handlerId,
		function(_OnActorReady: BindableEvent, OnNewTopic: BindableEvent, OnActorFinished: BindableEvent)
			OnActorReady = _OnActorReady
			self._OnNewTopicSignal = OnNewTopic
			self._OnActorFinishedSignal = OnActorFinished
			task.spawn(thread)
		end
	)
	if OnActorReady == nil then
		coroutine.yield()
	end
	task.defer(function()
		self._started = true
		OnActorReady:Fire(actor)
	end)
end

--[=[
	@method _OnTaskFinished
	@within ParallelJobActor
	@private

	Called when a task is finished.

	@param topic string -- Topic name
]=]
function ParallelJobActor:_OnTaskFinished(topic: string, ...: any): ()
	self._OnActorFinishedSignal:Fire(self._actor, topic, ...)
end

function ParallelJobActor:_NewTopic(topic: string): ()
	if self._started then
		error(`Cannot create new topics after job has started!`)
	end
	self._OnNewTopicSignal:Fire(topic)
end

--[=[
	@method BindToMessage
	@within ParallelJobActor

	Binds a callback to messages sent with the given topic.

	@param topic string -- Message topic
	@param callback (topic: Topic, ...any) -> ...any -- Callback to run when message is received
	@return RBXScriptConnection -- The connection
]=]
function ParallelJobActor:BindToMessage(topic: string, callback: (topic: Topic, ...any) -> ...any): RBXScriptConnection
	if self._started then
		error(
			`Cannot bind to message after job has started! Make sure to call ParallelJobActor:BindToMessage() immediately after calling Job.getActor()`
		)
	end
	self:_NewTopic(topic)
	return self._actor:BindToMessage(topic, function(...: any)
		self:_OnTaskFinished(topic, callback(...))
	end)
end

--[=[
	@method BindToMessageParallel
	@within ParallelJobActor

	Binds a callback to messages sent with the given topic.
	Runs the callback in parallel.

	@param topic string -- Message topic
	@param callback (topic: Topic, ...any) -> ...any -- Callback to run when message is received
	@return RBXScriptConnection -- The connection
]=]
function ParallelJobActor:BindToMessageParallel(
	topic: string,
	callback: (topic: Topic, ...any) -> ...any
): RBXScriptConnection
	if self._started then
		error(
			`Cannot bind to message after job has started! Make sure to call ParallelJobActor:BindToMessageParallel() immediately after calling Job.getActor()`
		)
	end
	self:_NewTopic(topic)
	return self._actor:BindToMessageParallel(topic, function(...: any)
		self:_OnTaskFinished(topic, callback(...))
	end)
end

--[=[
	@method GetJobId
	@within ParallelJobActor

	Returns the job id of the job that the actor is running.

	@return string? -- The job id
]=]
function ParallelJobActor:GetJobId(): string?
	return self._actor:GetAttribute("JobId")
end

function ParallelJobActor:SetJobSharedTable(key: string, value: SharedTable?): ()
	SharedTableRegistry:SetSharedTable(`{self:GetJobId()}_{key}`, value)
end

function ParallelJobActor:GetJobSharedTable(key: string): SharedTable?
	return SharedTableRegistry:GetSharedTable(`{self:GetJobId()}_{key}`)
end

function ParallelJobActor:SetSharedTable(key: string, value: SharedTable?): ()
	self:SetJobSharedTable(`{self._actor.Name}_{key}`, value)
end

function ParallelJobActor:GetSharedTable(key: string): SharedTable?
	return self:GetJobSharedTable(`{self._actor.Name}_{key}`)
end

export type ParallelJobActor = typeof(ParallelJobActor.new(...)) & {
	-- functions
	new: () -> ParallelJobActor,
	-- methods
	BindToMessage: (self: ParallelJobActor, topic: string, callback: (topic: Topic, ...any) -> ...any) -> RBXScriptConnection;
	BindToMessageParallel: (self: ParallelJobActor, topic: string, callback: (topic: Topic, ...any) -> ...any) -> RBXScriptConnection;
	GetJobId: (self: ParallelJobActor) -> string?;
	_OnTaskFinished: (self: ParallelJobActor, topic: string, ...any) -> ();
	_Init: (self: ParallelJobActor) -> ();
}

--[=[
	@class JobActor

	Used to send messages to an actor.
]=]
local JobActor = {}
JobActor.__index = JobActor
local jobActors = {} -- {[Actor]: JobActor}

--[=[
	@function new
	@within JobActor
	@private
	@ignore

	Creates a new job actor used in Job scripts.

	@param actor Actor -- The actor to initialize
	@return JobActor -- The job actor
]=]
function JobActor.new(actor: Actor): JobActor
	local self = setmetatable({
		_actor = actor,
		_messagesPending = 0,
	}, JobActor)
	jobActors[actor] = self
	actor.Destroying:Connect(function()
		jobActors[actor] = nil
	end)
	return self
end

--[=[
	@function get
	@within JobActor

	Returns the JobActor from an Actor.

	@param actor Actor -- The actor
	@return JobActor -- The job actor
]=]
function JobActor.get(actor: Actor): JobActor
	local jobActor = jobActors[actor]
	if not jobActor then
		error(`Job Actor not found! Did you forget to call Job.getActor() inside of your Job script?`)
	end
	return jobActor
end

--[=[
	@method SetJobId
	@within JobActor

	Sets the job id of the job that the actor is currently performing a task for.

	@param jobId string? -- The job id
]=]
function JobActor:SetJobId(jobId: string?): ()
	self._actor:SetAttribute("JobId", jobId)
end

function JobActor:GetJobId(): string?
	return self._actor:GetAttribute("JobId")
end

--[=[
	@method SendMessage
	@within JobActor

	Sends a message to the actor.

	@param topic string -- Message topic
	@param ... any -- Message arguments
]=]
function JobActor:SendMessage(topic: string, ...: any): ()
	task.defer(self._actor.SendMessage, self._actor, topic, ...)
	self._messagesPending += 1
end

function JobActor:SetJobSharedTable(key: string, value: SharedTable?): ()
	SharedTableRegistry:SetSharedTable(`{self:GetJobId()}_{key}`, value)
end

function JobActor:GetJobSharedTable(key: string): SharedTable?
	return SharedTableRegistry:GetSharedTable(`{self:GetJobId()}_{key}`)
end

function JobActor:SetSharedTable(key: string, value: SharedTable?): ()
	self:SetJobSharedTable(`{self._actor.Name}_{key}`, value)
end

function JobActor:GetSharedTable(key: string): SharedTable?
	return self:GetJobSharedTable(`{self._actor.Name}_{key}`)
end

export type JobActor = typeof(JobActor.new(...)) & {
	-- functions
	new: (actor: Actor) -> JobActor;
	get: (actor: Actor) -> JobActor;
	-- methods
	SetJobId: (self: JobActor, jobId: string?) -> ();
	GetJobId: (self: JobActor) -> string?;
	SendMessage: (self: JobActor, topic: string, ...any) -> ();
}

--[=[
	@class Job

	Used to send messages to an actor.
]=]
local Job = {}
Job.__index = Job

--[=[
	@function new
	@within Job
	@private
	@ignore

	Creates a new job.

	@param handler JobHandler -- The job handler
	@return Job -- The job
]=]
function Job.new(handler, id: string?): Job
	local self = setmetatable({
		Id = id,
		Running = false, -- whether the job was cancelled or not
		OnFinished = Signal.new(),
		--
		_id = HttpService:GenerateGUID(false),
		_handler = handler,
		--
		_actorsReady = 0,
		_actorsRunning = 0, -- Number of actors currently performing the job
		--
		_jobFn = {} :: { [JobFn]: boolean }, -- [jobFn]: keepRunning
		_jobFnCount = 0,
		_onFinishedFn = {} :: { [string]: OnFinishedFn | true }, -- [topic]: onFinished
		-- Stats
		JobStats = {} :: {
			TotalTime: number,
		},
		-- TopicStats = {} :: {[string]: {
		-- 	runCount: number,
		-- 	sumDT: number,
		-- }}, -- [topic]: avgTime
	}, Job)
	-- Add job to handler
	handler._jobs[self._id] = self
	return self
end

--[=[
	@method _AddTopic
	@within Job
	@private

	Adds a topic to the job.

	@param topic string -- The topic to add
]=]
function Job:_AddTopic(topic: string): ()
	local onFinishedFn = self._onFinishedFn[topic]
	if onFinishedFn == nil then
		self._onFinishedFn[topic] = true
		-- self.TopicStats[topic] = {
		-- 	runCount = 0,
		-- 	sumDT = 0,
		-- }
	end
end

--[=[
	@method _AddJobFn
	@within Job
	@private

	Adds a job function to the job.

	@param jobFn (actor: JobActor) -> boolean? -- The job function to add
]=]
function Job:_AddJobFn(jobFn: JobFn): ()
	-- Return if job function was already added
	if self._jobFn[jobFn] ~= nil then
		return
	end
	self._jobFnCount += 1
	self._jobFn[jobFn] = true
	self._handler._totalJobFn += 1
	self._handler:_ScheduleRestart()
end

--[=[
	@method _RemoveJobFn
	@within Job
	@private

	Removes a job function from the job.

	@param jobFn (actor: JobActor) -> boolean? -- The job function to remove
]=]
function Job:_RemoveJobFn(jobFn: JobFn): ()
	self._jobFnCount -= 1
	self._jobFn[jobFn] = nil
	self._handler._totalJobFn -= 1
end

--[=[
	@method _FnCount
	@within Job
	@private

	Returns the number of job functions in the job.

	@return number -- The number of job functions
]=]
function Job:_FnCount(): number
	return self._jobFnCount
end

--[=[
	@method _GetJobFn
	@within Job
	@private

	Returns the next job function to run.

	@return (actor: JobActor) -> boolean? -- The job function
]=]
function Job:_GetJobFn(): JobFn?
	return next(self._jobFn)
end

--[=[
	@method _AddActor
	@within Job
	@private

	Called when an actor starts a task.
]=]
function Job:_AddActor(): ()
	self._actorsRunning += 1
end

--[=[
	@method _RemoveActor
	@within Job
	@private

	Called when an actor finishes a task.
]=]
function Job:_RemoveActor(): ()
	self._actorsRunning -= 1
	if self._actorsRunning == 0 and self._jobFnCount == 0 then
		self:_Finished()
	end
end

--[=[
	@method _TopicReturned
	@within Job
	@private

	Called when an actor finishes a task.

	@param actor Actor -- The actor that finished the task
	@param topic string -- The topic of the task
]=]
function Job:_TopicReturned(jobActor: JobActor, topic: string, ...: any): JobFn?
	-- Add stats
	-- local stats = self.TopicStats[topic]
	-- if stats then
	-- 	stats.runCount += 1
	-- 	stats.sumDT += dt
	-- end
	--
	jobActor._messagesPending -= 1
	local onFinishedFn = self._onFinishedFn[topic]
	--
	if onFinishedFn and onFinishedFn ~= true then
		local jobFn = onFinishedFn(jobActor, ...)
		if jobFn then
			self:_AddJobFn(jobFn)
			return jobFn
		end
	end
	return
end

--[=[
	@method _Finished
	@within Job
	@private

	Called when the job is finished.
]=]
function Job:_Finished(): ()
	if self._debug then
		self.JobStats.TotalTime = os.clock() - self.JobStats.TotalTime
		-- Debug message
		local str = `\nJob '{self.Id}' Finished:\nTotal Time: {self.JobStats.TotalTime};\n`
		-- str ..= 'Topic Stats:\n'
		-- for topic, stats in pairs(self.TopicStats) do
		-- 	str ..= `Topic '{topic}' -> Run Count: {stats.runCount}; Avg. Per Node: {stats.sumDT / stats.runCount};\n`
		-- end
		warn(str)
	end
	--
	self.Running = false
	self.OnFinished:Fire(self.TopicStats)
end

--[=[
	@method BindTopic
	@within Job

	Binds a callback to a topic.
	- The callback can receive data from actors and return a new job function (optional) to run.

	@param topic string -- The topic to bind to
	@param handler (actor: Actor, ...any) -> (JobFn?) -- The callback to run when the topic is finished
]=]
function Job:BindTopic(topic: string, handler: OnFinishedFn): ()
	if not self._handler:HasTopic(topic) then
		error(`Topic '{topic}' does not exist!`)
	end
	if self.Running then
		error(`Cannot set finished handler while job is running!`)
	end
	self._onFinishedFn[topic] = handler
end

--[=[
	@method Run
	@within Job

	Adds a task to the job.
	- The task function should interact with (send messages to) the actors.
	- The task function will be called until it returns false.

	- The finished callbacks should receive data from actors and (optional) return a new job function to run.
	@param topicFinishedCallbacks {[string]: (actor: Actor, ...any) -> (JobFn?)} -- Callbacks to run when a topic is finished

	@param mainJobFn (actor: Actor) -> boolean? -- The job function to run
]=]
function Job:Run(jobFn: (actor: Actor) -> boolean?): ()
	if not self._handler.IsReady then
		self._handler.OnReady:Wait()
	end
	if not self.Running then
		self.Running = true
		self.JobStats.TotalTime = os.clock()
	end
	self:_AddJobFn(jobFn)
end

--[=[
	@method OnFinish
	@within Job

	Returns a promise that resolves when the job is finished.
]=]
function Job:OnFinish(): Promise
	return not self.Running and Promise.resolve() or Promise.fromEvent(self.OnFinished)
end

function Job:NumActors(): number
	return self._actorsRunning
end

export type Job = typeof(Job.new(...)) & {
	-- functions
	new: (handler: JobHandler) -> Job;
	-- methods
	_AddTopic: (self: Job, topic: string) -> ();
	_AddJobFn: (self: Job, jobFn: JobFn) -> ();
	_RemoveJobFn: (self: Job, jobFn: JobFn) -> ();
	_FnCount: (self: Job) -> number;
	_GetJobFn: (self: Job) -> JobFn?;
	_AddActor: (self: Job) -> ();
	_RemoveActor: (self: Job) -> ();
	_TopicReturned: (self: Job, jobActor: JobActor, topic: string, ...any) -> JobFn?;
	_Finished: (self: Job) -> ();
	BindTopic: (self: Job, topic: string, handler: OnFinishedFn) -> ();
	Run: (self: Job, jobFn: (actor: Actor) -> boolean?) -> ();
	OnFinish: (self: Job) -> Promise;
}


--[=[
	@class JobHandler

	Used to run a script in parallel on multiple actors.
	Automatically manages actors and communication between them.
]=]
local JobHandler = {}
JobHandler.__index = JobHandler

-- export type MainJobFn = (actor: Actor) -> boolean?
export type JobFn = (actor: JobActor) -> boolean?
export type OnFinishedFn = (actor: JobActor, ...any) -> JobFn?

--[=[
	@function new
	@within JobHandler

	Creates a new job.

	@param jobScript Script -- Script to run in parallel
	@param actors number? -- Number of actors to create
	@return Job
]=]
function JobHandler.new(jobScript: Script, actors: number, debug: boolean?)
	if typeof(jobScript) ~= "Instance" then
		error(`Invalid job script: expected type 'Script', got '{typeof(jobScript)}'`)
	elseif not jobScript:IsA("Script") then
		if jobScript:IsA("LocalScript") then
			error(`Invalid job script: Please use a 'Script' and set 'RunContext' property to 'Client' instead of using 'LocalScript'.`)
		end
		error(`Invalid job script: expected type 'Script', got '{script.ClassName}'`)
	end
	if jobScript.RunContext == Enum.RunContext.Legacy then
		error(`Invalid RunContext: Please set 'RunContext' property to 'Server' or 'Client'`)
	end
	local self = setmetatable({
		ActorCount = actors or DEFAULT_NUM_ACTORS,
		IsReady = false,
		OnReady = Signal.new(),
		--
		_id = `{jobScript.Name}_{HttpService:GenerateGUID(false)}`,
		_debug = debug or nil,
		_actors = {} :: { [Actor]: boolean }, -- [actor]: running
		_activeActors = 0, -- Number of actors currently performing a task
		_scheduledRestart = nil,
		_totalJobFn = 0,
		_topics = {} :: { [string]: true },
		--
		_jobs = {} :: { [string]: Job }, -- [jobId]: job,
	}, JobHandler)

	handlers[self._id] = self

	-- Create job folder
	local folder = Instance.new("Folder")
	folder.Name = "Job"
	folder.Parent = script
	-- Create event
	local OnActorFinished = Instance.new("BindableEvent")
	OnActorFinished.Name = "OnActorFinished"
	OnActorFinished.Parent = folder
	local OnActorReady = Instance.new("BindableEvent")
	OnActorReady.Name = "OnActorReady"
	OnActorReady.Parent = folder
	local OnNewTopic = Instance.new("BindableEvent")
	OnNewTopic.Name = "OnNewTopic"
	OnNewTopic.Parent = folder
	self._OnActorFinished = OnActorFinished
	self._OnActorReady = OnActorReady
	self._OnNewTopic = OnNewTopic
	-- OnActorReady
	local actorsReady = 0
	OnActorReady.Event:Connect(function(actor: Actor)
		actorsReady += 1
		if actorsReady == self.ActorCount then
			self.IsReady = true
			self.OnReady:Fire()
		end
	end)
	-- OnNewTopic
	OnNewTopic.Event:Connect(function(topic: string)
		self._topics[topic] = true
	end)
	-- OnActorFinished
	OnActorFinished.Event:Connect(function(actor: Actor, topic: string, ...: any)
		self:_TopicReturned(actor, topic, ...)
	end)
	-- Create actors
	local oldName = jobScript.Name
	jobScript.Name = self._id
	for i = 1, self.ActorCount do
		local actor = Instance.new("Actor")
		actor.Name = i
		actor.Parent = folder
		self._actors[actor] = false
		JobActor.new(actor)
		-- Add script
		local _jobScript = jobScript:Clone()
		_jobScript.Parent = actor
		_jobScript.Enabled = true
		actor:SendMessage(self._id, self._OnActorReady, self._OnNewTopic, self._OnActorFinished)
		--
	end
	jobScript.Name = oldName
	--
	return self
end

--[=[
	@function getActor
	@within JobHandler

	Returns a job script's ParallelJobActor from an Actor.
	Only call this inside of a job script.

	@return ParallelJobActor
]=]
function JobHandler.getActor(): ParallelJobActor
	return ParallelJobActor.new()
end

--[=[
	@method Destroy
	@within JobHandler

	Destroys the job.
]=]
function JobHandler:Destroy(): ()
	handlers[self._id] = nil
	for actor in pairs(self._actors) do
		for _, script in ipairs(actor:GetChildren()) do
			script.Enabled = false
		end
		actor:Destroy()
	end
	self.Running = false
	self.IsReady = true
	self.OnReady:Destroy()
	self.OnFinished:Fire(self.TopicStats)
	self.OnFinished:Destroy()
end

--[=[
	@method HasTopic
	@within JobHandler

	Returns whether the given topic is registered (actor called :BindToMessage(topic) or :BindToMessageParallel(topic))

	@param topic string -- The topic to check
	@return boolean -- Whether the job has the topic or not
]=]
function JobHandler:HasTopic(topic: string): boolean
	return self._topics[topic] == true
end

--[=[
	@method _GetJob
	@within JobHandler
	@private

	Returns the job with the given id.

	@param jobId string -- The job id
	@return Job -- The job
]=]
function JobHandler:_GetJob(jobId: string): Job
	local job = self._jobs[jobId]
	if not job then
		error(`Job '{jobId}' not found!`)
	end
	return job
end

--[=[
	@method _GetJobFn
	@within JobHandler
	@private

	Returns the next job function to run.

	@return (actor: JobActor) -> boolean? -- The job function
]=]
function JobHandler:_GetJobFn(): (JobFn?, Job?)
	for _, job in pairs(self._jobs) do
		if job:_FnCount() == 0 then
			continue
		end
		local jobFn = job:_GetJobFn()
		if jobFn then
			return jobFn, job
		end
	end
	return
end

--[=[
	@method _RunJobFn
	@within JobHandler
	@private

	Calls a job function.

	@param actor Actor -- The actor to run the job function on
	@return boolean -- Whether a job function was run on the actor or not
]=]
function JobHandler:_RunJobFn(actor: Actor): boolean
	local jobFn, job = self:_GetJobFn()
	if not jobFn then
		return false
	end
	if self._actors[actor] ~= true then
		self._activeActors += 1
		self._actors[actor] = true
	end
	job:_AddActor()
	local jobActor: JobActor = JobActor.get(actor)
	local running = true
	task.spawn(function()
		jobActor._messagesPending = 0
		jobActor:SetJobId(job._id)
		local _stopRunning = jobFn(jobActor)
		running = false
		if _stopRunning == true then
			job:_RemoveJobFn(jobFn)
		end
		if jobActor._messagesPending == 0 then
			self:_ActorFinished(jobActor, job)
		end
	end)
	if running then
		error(
			`Job function cannot yield! This may cause unnecessary calls to the job function because its running status is not updated until it returns.`
		)
	end
	return true
end

--[=[
	@method _ScheduleRestart
	@within JobHandler
	@private

	Schedules a restart on inactive actors.
]=]
function JobHandler:_ScheduleRestart(): ()
	-- Return if job function was already added
	if not self._scheduledRestart then
		self._scheduledRestart = true
		task.defer(function()
			self._scheduledRestart = nil
			for actor, isRunning in pairs(self._actors) do
				if not isRunning then
					-- Run job, return if there are no more job functions to run
					if not self:_RunJobFn(actor) then
						return
					end
				end
			end
		end)
	end
end

--[=[
	@method _SetActorInactive
	@within JobHandler
	@private

	Called when an actor finishes a task.

	@param jobActor JobActor -- The job actor
	@param job Job? -- The job that the actor was running
]=]
function JobHandler:_SetActorInactive(jobActor: JobActor, job: Job?): ()
	jobActor:SetJobId(nil)
	self._activeActors -= 1
	self._actors[jobActor._actor] = false
end

--[=[
	@method _TopicReturned
	@within JobHandler
	@private

	Called when an actor returned data from a topic.

	@param dt number -- The time it took to run the task
	@param actor Actor -- The actor that finished the task
	@param topic string -- The topic of the task
]=]
function JobHandler:_TopicReturned(actor: Actor, topic: string?, ...: any): ()
	-- Add stats
	-- local stats = self.TopicStats[topic]
	-- if stats then
	-- 	stats.runCount += 1
	-- 	stats.sumDT += dt
	-- end
	--
	local jobActor: JobActor = JobActor.get(actor)
	local job = self:_GetJob(jobActor:GetJobId())
	--
	if topic then
		job:_TopicReturned(jobActor, topic, ...)
	end
	-- Find another job fn to run
	if jobActor._messagesPending == 0 then
		self:_ActorFinished(jobActor, job)
	end
end

--[=[
	@method _ActorFinished
	@within JobHandler
	@private

	Called when an actor finishes a task.

	@param jobActor JobActor -- The job actor
	@param job Job? -- The job that the actor was running
]=]
function JobHandler:_ActorFinished(jobActor: JobActor, job: Job): ()
	if job then
		job:_RemoveActor()
	end
	if self._totalJobFn == 0 then
		self:_SetActorInactive(jobActor, job)
	else
		self:_RunJobFn(jobActor._actor)
	end
end

--[=[
	@method GetActors
	@within JobHandler

	Returns the job handler's actors.

	@return { [Actor]: any }
]=]
function JobHandler:GetActors(): { [Actor]: any }
	return self._actors
end

--[=[
	@method NewJob
	@within JobHandler

	Creates a new job.

	@return Job
]=]
function JobHandler:NewJob(Id: string?): Job
	return Job.new(self, Id)
end

--[=[
	@method Run
	@within JobHandler

	Creates a new job and runs it.
	- The job function should interact with (send messages to) the actors.
	- The job function will be called until it returns false.

	- The finished callbacks should receive data from actors and return a new job function (optional) to run.

	@param jobFn (actor: Actor) -> boolean? -- The initial job function to run
]=]
function JobHandler:Run(jobFn: (actor: Actor) -> boolean?, topicHandlers: {[string]: OnFinishedFn}?, Id: string?): Promise
	local job: Job = self:NewJob(Id)
	if not self.IsReady then
		self.OnReady:Wait()
	end
	if topicHandlers then
		for topic, handler in pairs(topicHandlers) do
			job:BindTopic(topic, handler)
		end
	end
	job:Run(jobFn)
	return job:OnFinish():finallyCall(self.Remove, self, job)
end

--[=[
	@method Remove
	@within JobHandler

	Removes a job from the job handler.

	@param job Job -- The job to remove
]=]
function JobHandler:Remove(job: Job): ()
	self._totalJobFn -= job._jobFnCount
	self._jobs[self._id] = nil
	for actor in pairs(self._actors) do
		local jobActor = JobActor.get(actor)
		if job._id == jobActor:GetJobId() then
			if self._totalJobFn == 0 then
				self:_SetActorInactive(jobActor)
			else
				self:_RunJobFn(actor)
			end
		end
	end
end

export type JobHandler = typeof(JobHandler.new(...)) & {
	-- functions
	new: (jobScript: Script, actors: number, debug: boolean?) -> JobHandler;
	getActor: () -> ParallelJobActor;
	-- methods
	Destroy: (self: JobHandler) -> ();
	HasTopic: (self: JobHandler, topic: string) -> boolean;
	_GetJob: (self: JobHandler, jobId: string) -> Job;
	_GetJobFn: (self: JobHandler) -> (JobFn?, Job?);
	_RunJobFn: (self: JobHandler, actor: Actor) -> boolean;
	_ScheduleRestart: (self: JobHandler) -> ();
	_SetActorInactive: (self: JobHandler, jobActor: JobActor, job: Job?) -> ();
	_TopicReturned: (self: JobHandler, jobId: string, actor: Actor, topic: string, ...any) -> ();
	GetActors: (self: JobHandler) -> { [Actor]: any };
	NewJob: (self: JobHandler) -> Job;
	Run: (self: JobHandler, jobFn: (actor: Actor) -> boolean?) -> Promise;
	Remove: (self: JobHandler, job: Job) -> ();
}
type Promise = typeof(Promise.new(...))
return JobHandler