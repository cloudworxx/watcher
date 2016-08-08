url = require 'url'
path = require 'path'
fs = require 'fs'
mkdirp = require 'mkdirp'
npm = require 'npm'
vm = require 'vm'
extend = require('util')._extend
Config = require './Config'

class Sandbox
  constructor : (repo, @file, cb) ->
    # Set policy uri, ref, name and path
    @uri = repo.uri
    @ref = repo.ref or 'master'
    @lang = repo.lang or 'javascript'
    @ext = {
      'javascript': 'js'
      'coffeescript': 'coffee'
      'icedcoffeescript': 'iced'
    }[@lang]
    @queue = []
    @ready = false

    @name = url.parse(@uri).pathname.slice(1).replace(/\.git/g, '')
    if @ref isnt 'master'
      @name += "/#{ref}"
    @path = path.normalize "#{Config.policies_dir}/#{@name}"
    @abs = path.resolve @path
    #console.log @path, @abs

    # Make sure that path exists
    await mkdirp @path, defer err
    # Pull repository contents
    await @pull defer()
    # Install dependencies
    await @install defer npmData
    console.log "[NPM] Installed #{npmData.length} new packages"
    # Retrieve code and compile to JS
    await fs.readFile "#{@path}/main.#{@ext}", 'utf8', defer err, code
    code = @toJS code
    # Start virtualization
    @virtualize code, repo.params

    cb and cb this

  pull : (cb) ->
    console.log "[SANDBOX] Pulling repository contents from #{@uri}"
    @git = require('simple-git')(@path).init()
    await @git.getRemotes 'origin', defer err, remotes
    for remote in remotes
      @git.removeRemote(remote.name) if remote.name.length > 0
    @git
      .addRemote('origin', @uri)
      .pull('origin', @ref)
      .checkout(@ref)
      .then cb

  toJS : (code) ->
    switch @lang
      when 'javascript'
        code
      when 'coffeescript'
        require('coffee-script').compile code, {header: false, bare: true}
      when 'icedcoffeescript'
        require('iced-coffee-script').compile code, {header: false, bare: true}

  install : (cb) =>
    console.log '[SANDBOX] Installing dependencies...'
    await fs.readFile "#{@abs}/package.json", 'utf8', defer err, json
    deps = Object.keys JSON.parse(json).dependencies
    await npm.load {prefix: @abs}, defer err
    await npm.commands.install deps, defer err, data
    cb data

  virtualize : (code, params) =>
    @vm = vm.createContext
      require: (mod) =>
        try
          require mod
        catch e
          require "#{@abs}/node_modules/#{mod}"
      console:
        log: (first, others...) =>
          console.log "[POLICY][#{@name}]:\n> #{first}", others...
      module: {}
      iced: require('iced-coffee-script').iced
    vm.runInContext code, @vm,
      displayErrors: true
    vm.runInContext "policy = new this.module.exports(#{JSON.stringify(params)})", @vm
    console.log "[POLICY][#{@name}] Ready!"

    @ready = true
    for {diff, meta} in @queue
      @send diff, meta
    @queue = []

  send : (diff, meta) =>
    if @ready
      if @vm?.module?.exports?
        payload = extend meta,
          diff: diff
          path: @file
          date: Date.now()
        vm.runInContext "policy.receiver(#{JSON.stringify(payload)})", @vm
    else
      console.log "[SANDBOX] #{@name or @uri} is not ready yet, queuing event (#{@queue.length + 1})"
      @queue.push {diff, meta}

module.exports = Sandbox
