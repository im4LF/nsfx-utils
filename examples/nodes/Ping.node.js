
const sleep = ms =>
  new Promise(resolve => setTimeout(resolve, ms))

const MAX_LIMIT = 0.5

module.exports = (args, env) => ({
  out_: 1,
  errors_: 1,
  async _in(message, done) {
    const value = Math.random()
    await sleep(value)

    if (value > MAX_LIMIT) {
      message.error = {
        code: 'GT_MAX_LIMIT',
        limit: MAX_LIMIT,
        value,
      }
      this.send('errors', message)
    } else {
      message.data = {
        value,
      }
      this.send('out', message)
    }
    done()
  }
})