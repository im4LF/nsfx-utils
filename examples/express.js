const args = require('yargs')
  .options({
    port: {
      default: 8000,
    },
  })
  .argv

const path = require('path')
const pino = require('pino')
const { build } = require('../index')
const express = require('express')

const logics = {
  hello: {
    ...require('./flows/hello.flow.js'),
  },
  ping: {
    ...require('./flows/ping.flow.js'),
  },
}

const env = {
  logger: pino({
    transport: {
      target: 'pino-pretty',
    },
  }),
  nodesdir: __dirname,
}

async function init_flows() {
  for (const [name, logic] of Object.entries(logics)) {
    const flow = await new Promise((resolve, reject) =>
      build(
        logic.def,
        logic.data,
        env,
        (err, flow) => err
          ? reject(err)
          : resolve(flow)
      )
    )

    logics[name].flow = flow
  }
}

async function init_routes(app) {
  const routes = [{
    method: 'get',
    route: '/hello',
    flow: 'hello'
  },{
    method: 'get',
    route: '/ping',
    flow: 'ping'
  }]

  for (const item of routes) {
    app[item.method](
      item.route,
      (rq, rs) =>
        logics[item.flow].flow.start.in.write({ rq, rs })
    )
  }
}

async function main() {
  const LOG_TAG = 'main'
  try {
    await init_flows()
  } catch (err) {
    env.logger.error(err, LOG_TAG)
    process.exit(1)
  }

  const app = express()
  init_routes(app)

  app.listen(args.port)
  env.logger.info(args.port, `${LOG_TAG} / webserver listen`)
}

main()