module.exports = (args, env) => ({
  out_: 1,
  errors_: 1,
  async _in(message, done) {
    message.data = {
      rnd: Math.random(),
      msg: 'hello',
    }
    this.send('out', message, done)
  }
})