url = require 'url'
path = require 'path'
fs = require 'fs'
mkdirp = require 'mkdirp'
npm = require 'npm'
vm = require 'vm'
NodeVM = require('vm2').NodeVM
Config = require './Config'

class Sandbox
  constructor : (repo, cb) ->
    # Set policy uri, ref, name and path
    @uri = repo.uri
    @ref = repo.ref or 'master'
    @lang = repo.language or 'javascript'
    @ext = {
      'javascript': 'js'
      'coffeescript': 'coffee'
      'icedcoffeescript': 'iced'
    }[@lang]

    @name = url.parse(@uri).pathname.slice(1).replace(/\.git/g, '')
    if @ref isnt 'master'
      @name += "/#{ref}"
    @path = path.normalize "#{Config.policies_dir}/#{@name}"
    @abs = path.resolve @path

    # Make sure that path exists
    await mkdirp @path, defer err
    # Pull repository contents
    await @pull defer()
    # Install dependencies
    await @install defer npmData
    # Retrieve code and compile to JS
    await fs.readFile "#{@path}/main.#{@ext}", 'utf8', defer err, code
    code = @toJS code
    # Start virtualization
    @virtualize(code, repo.params)

    cb and cb this

  pull : (cb) ->
    console.log 'Pulling repository contents...'
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


  install : (cb) ->
    console.log 'Installing dependencies...'
    await fs.readFile "#{@abs}/package.json", 'utf8', defer err, json
    deps = Object.keys JSON.parse(json).dependencies
    await npm.load {prefix: @abs}, defer err
    await npm.commands.install deps, defer err, data
    cb data

  virtualize : (code, params) ->
    console.log 'Virtualizing...'
    @vm = vm.createContext
      require: (mod) ->
        try
          require mod
        catch e
          require "#{@abs}/node_modules/#{mod}"
      console: console
      module: module
    vm.runInContext code, @vm
    vm.runInContext "policy = new this.module.exports(#{JSON.stringify(params)})", @vm

  send : (o) =>
    vm.runInContext "policy.receiver(#{JSON.stringify(o)})", @vm

module.exports = Sandbox