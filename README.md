

## Concept

`Flow` - flow consists of `processes` and `connections`

`Process` - process is an atomic operation containing `in ports` and `out ports`. Each process is based on `Node`

`Node` - defenition of behavior for processes. Node can have `props`, `input ports`, `out ports`

`Connection` - connections between ports of processes 

## Flow example

```bash
# main loop
# each process is defined as name_of_process(path/to/Node)
ticks(./Ticks) -> locker(./Locks) -> tasks(./pg/ArrayQuery) -> dispatch(./Dummy)

# when task is started notify wait process about it
dispatch START -> wait(./Wait)

# when task is done notify wait process about it
dispatch DONE -> DONE wait

# when wait process knows that all tasks are started, then it pushes message to ALLDONE port
wait ALLDONE -> NEXT tasks

# when done
tasks DONE -> UNLOCK locker
```

Each process can be initialized with args in flow definition, for example:

```bash
ticks(./Ticks, {"interval": 3000}) -> tasks(./pg/ArrayQuery, {"sql":"select * from some.table where p = $1", "values":[ 123 ]})
```

Or args can be defined outside 

```js
const data = {
    ticks: {
        interval: 5000
    },
    tasks: {
        dsn: dsn1,
        sql: `
            select 
                *
            from some.table
            where 
                p = $1
            limit $2
        `,
        values: message => [ 123, 12 ],
        shiftBy: 2,
        out: 'task'
    }
}
```

And passed to flow builder

```js

build(flow_def, data, (err, flow) => {

})

```

## Node examples

### Ticks node

props:
- `interval`

inports:
- `start`
- `stop`

outports:
- `out`

```js
const Ticks = {
    // props that must be initialized 
    props: {
        interval: { default: 1000 }
    },
    // in ports named with underscore at start
    _start(message, done) {
        let interval = typeof this.props.interval === 'function' ? this.props.interval(message) : this.props.interval
        this.send('out', { t: Date.now() }, done)
        this.__timer = setInterval(_ => this.send('out', { t: Date.now() }), interval)
    },
    _stop(message, done) {
        if (this.__timer) clearInterval(this.__timer)
        done()
    },
    // out ports named with underscore at end
    out_: 1
}
```

### Locks node

```js
const Locks = {
    _in(message, done) {
        if (this.locked) {
            this.logger.info({ locked: this.locked }, this.name + '_in')
            this.send('pass', message, done)
        }
        else {
            this.locked = true
            this.send('out', message, done)
        }
    },
    out_: 1,
    pass_: 1,
    _unlock(message, done) {
        this.logger.info(message, this.name + '_reset')
        this.locked = false
        done()
    }
}
```

### ArrayQuery node

props:
- `dsn` - connection string
- `sql` - string or function generator for sql
- `values` - array of function generator for values
- `shiftBy` - count of parallel shifting in out port
- `out` - datakey for each row pushed into message

inports:
- `in`
- `next`

outports:
- `out`
- `errors`
- `done`

```js
const ArrayQuery = {
    props: {
        dsn: { required: true },
        sql: [String,Function],
        values: [Array,Function],
        shiftBy: { type: Number, default: 1 },
        out: { default: 'item' }
    },
    out_: 1,
    errors_: 1,
    done_: 1,
    // each node can have init function
    init(done) {
        this.__pool = getPool(this.props.dsn)
        done(null, this)
    },
    _in(message, done) {
        
        let sql = typeof this.props.sql === 'function' ? this.props.sql(message) : this.props.sql
        let values = typeof this.props.values === 'function' ? this.props.values(message) : this.props.values

        this.logger.info({ dsn: this.props.dsn, sql, values }, this._name)

        this.__pool.query(sql, values, (err, res) => {
            if (err) {
                this.logger.error(err)
                message.error = err
                this.send('errors', message, done)
            }
            else {
                this.__items = res.rows
                this._next(message, done)
            }
        })
    },
    _next(message, done) {
        let buf = this.__items.splice(0, this.props.shiftBy)
        if (!buf.length) {
            this.send('done', message)
        }
        else {
            buf.forEach(item => {
                this.send('out', { ...message, [ this.props.out ]: item })
            })
        }
        done()
    }
}
```

## Experimental nodes definition

Define node as a function with some useful input arguments, for example:
- `env` - environment of flow, can contain `logger`

```js
const Locks = env => ({
    _in(message, done) {
        if (this.locked) {
            env.logger.info({ locked: this.locked }, this.name + '_in')
            this.send('pass', message, done)
        }
        else {
            this.locked = true
            this.send('out', message, done)
        }
    },
    out_: 1,
    pass_: 1,
    _unlock(message, done) {
        env.logger.info(message, this.name + '_reset')
        this.locked = false
        done()
    }
})
```