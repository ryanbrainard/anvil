uuid = require("node-uuid")

class Builder

  constructor: () ->
    @id      = uuid.v4()
    @spawner = require("spawner").init()
    @storage = require("storage").init()

  build: (source, options, cb) ->
    ext = if options.type is "deb" then "deb" else "tgz"
    @storage.generate_put_url "slug/#{@id}.#{ext}", (err, slug_put_url) =>
      @storage.generate_put_url "exit/#{@id}", (err, exit_put_url) =>
        @storage.generate_put_url "process_types/#{@id}", (err, process_types_put_url) =>
          @storage.generate_put_url "config_vars/#{@id}", (err, config_vars_put_url) =>
            @storage.generate_put_url "addons/#{@id}", (err, addons_put_url) =>
              @storage.generate_put_url "framework/#{@id}", (err, framework_put_url) =>
                env =
                  ANVIL_HOST:             process.env.ANVIL_HOST
                  BUILDPACK_URL:          options.buildpack
                  CACHE_URL:              @cache_with_default(options.cache)
                  EXIT_PUT_URL:           exit_put_url
                  NODE_ENV:               process.env.NODE_ENV
                  NODE_PATH:              process.env.NODE_PATH
                  PATH:                   process.env.PATH
                  SLUG_ID:                @id
                  SLUG_URL:               @slug_url(options.type)
                  SLUG_PUT_URL:           slug_put_url
                  SLUG_TYPE:              ext
                  SOURCE_URL:             source
                  PROCESS_TYPES_PUT_URL:  process_types_put_url
                  ADDONS_PUT_URL:         addons_put_url
                  CONFIG_VARS_PUT_URL:    config_vars_put_url
                  FRAMEWORK_PUT_URL:      framework_put_url
                env[key] = val for key, val of JSON.parse(options.env || "{}")
                builder  = @spawner.spawn("bin/compile-wrapper $SOURCE_URL", env:env)
                cb builder, this
                builder.emit "data", "Launching build process... "

  build_request: (req, res, logger) ->
    options =
      buildpack: req.body.buildpack
      cache:     req.body.cache
      env:       req.body.env
      keepalive: req.body.keepalive
      type:      req.body.type


    require("builder").init().build req.body.source, options, (build, builder) ->

      res.writeHead 200
        "Content-Type":        "text/plain"
        "Transfer-Encoding":   "chunked"
        "X-Cache-Url":         builder.cache_url
        "X-Manifest-Id":       builder.id
        "X-Slug-Url":          builder.slug_url(req.body.type)
        "X-Exit-Url":          builder.url_for('exit')
        "X-Config-Vars-Url":   builder.url_for('config_vars')
        "X-Process-Types-Url": builder.url_for('process_types')
        "X-Addons-Url":        builder.url_for('addons')
        "X-Framework-Url":     builder.url_for('framework')

      if options.keepalive
        ping = setInterval (->
          try
            res.write "\0\0\0"
          catch error
            console.log "error writing to socket"
            clearInterval ping
        ), 1000

      build.on "data", (data)   ->
        exit_header = "ANVIL!EXITCODE:"
        if (pos = data.toString().indexOf(exit_header)) > -1
          res.write data.slice(0, pos)
          code = data[pos + exit_header.length]
          res.addTrailers
            "X-Exit-Code": code.toString()
        else
          res.write(data)
      build.on "end", (success) ->
        clearInterval ping if ping
        logger.finish()
        res.end()

  cache_with_default: (cache) ->
    @cache_url = cache
    if (cache || "") is "" then @cache_url = @storage.create_cache()
    @cache_url

  url_for: (key, ext) ->
    "#{process.env.ANVIL_HOST}/#{key}/#{@id}" + if ext then ".#{ext}" else ""

  slug_url: (type) ->
    @url_for('slugs', if type is "deb" then "deb" else "tgz")

module.exports.init = () ->
  new Builder()
