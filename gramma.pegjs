/*
 * Classic example grammar, which recognizes simple arithmetic expressions like
 * "2*(3+4)". The parser generated from this grammar then computes their value.
 */

{
  var parser, edges, nodes;

  var defaultInPort = "IN", defaultOutPort = "OUT";

  parser = this;
  delete parser.properties;
  delete parser.inports;
  delete parser.outports;
  delete parser.groups;

  edges = parser.edges = [];

  nodes = {};

  var serialize, indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  parser.validateContents = function(graph, options) {
    // Ensure all nodes have a component
    if (graph.processes) {
      Object.keys(graph.processes).forEach(function (node) {
        if (!graph.processes[node].component) {
          throw new Error('Node "' + node + '" does not have a component defined');
        }
      });
    }
    // Ensure all inports point to existing nodes
    if (graph.inports) {
      Object.keys(graph.inports).forEach(function (port) {
        var portDef = graph.inports[port];
        if (!graph.processes[portDef.process]) {
          throw new Error('Inport "' + port + '" is connected to an undefined target node "' + portDef.process + '"');
        }
      });
    }
    // Ensure all outports point to existing nodes
    if (graph.outports) {
      Object.keys(graph.outports).forEach(function (port) {
        var portDef = graph.outports[port];
        if (!graph.processes[portDef.process]) {
          throw new Error('Outport "' + port + '" is connected to an undefined source node "' + portDef.process + '"');
        }
      });
    }
    // Ensure all edges have nodes defined
    if (graph.connections) {
      graph.connections.forEach(function (edge) {
        if (edge.tgt && !graph.processes[edge.tgt.process]) {
          if (edge.data) {
            throw new Error('IIP containing "' + edge.data + '" is connected to an undefined target node "' + edge.tgt.process + '"');
          }
          throw new Error('Edge from "' + edge.src.process + '" port "' + edge.src.port + '" is connected to an undefined target node "' + edge.tgt.process + '"');
        }
        if (edge.src && !graph.processes[edge.src.process]) {
          throw new Error('Edge to "' + edge.tgt.process + '" port "' + edge.tgt.port + '" is connected to an undefined source node "' + edge.src.process + '"');
        }
      });
    }
  };

  parser.addNode = function (nodeName, comp) {
    if (!nodes[nodeName]) {
      nodes[nodeName] = {}
    }
    if (!!comp.comp) {
      nodes[nodeName].component = comp.comp;
    }
    if (!!comp.meta) {
      nodes[nodeName].metadata=comp.meta;
    }

  }

  var anonymousIndexes = {};
  var anonymousNodeNames = {};
  parser.addAnonymousNode = function(comp, offset) {
      if (!anonymousNodeNames[offset]) {
          var componentName = comp.comp.replace(/[^a-zA-Z0-9]+/, "_");
          anonymousIndexes[componentName] = (anonymousIndexes[componentName] || 0) + 1;
          anonymousNodeNames[offset] = "_" + componentName + "_" + anonymousIndexes[componentName];
          this.addNode(anonymousNodeNames[offset], comp);
      }
      return anonymousNodeNames[offset];
  }

  parser.getResult = function () {
    var result = {
      inports: parser.inports || {},
      outports: parser.outports || {},
      groups: parser.groups || [],
      processes: nodes || {},
      connections: parser.processEdges()
    };

    if (parser.properties) {
      result.properties = parser.properties;
    }
    result.caseSensitive = options.caseSensitive || false;

    parser.validateContents(result);

    return result;
  }

  var flatten = function (array, isShallow) {
    var index = -1,
      length = array ? array.length : 0,
      result = [];

    while (++index < length) {
      var value = array[index];

      if (value instanceof Array) {
        Array.prototype.push.apply(result, isShallow ? value : flatten(value));
      }
      else {
        result.push(value);
      }
    }
    return result;
  }

  parser.registerAnnotation = function (key, value) {
    if (!parser.properties) {
      parser.properties = {};
    }

    if (key === 'runtime') {
      parser.properties.environment = {};
      parser.properties.environment.type = value;
      return;
    }

    parser.properties[key] = value;
  };

  parser.registerInports = function (node, port, pub) {
    if (!parser.inports) {
      parser.inports = {};
    }

    if (!options.caseSensitive) {
      pub = pub.toLowerCase();
      port = port.toLowerCase();
    }

    parser.inports[pub] = {process:node, port:port};
  }
  parser.registerOutports = function (node, port, pub) {
    if (!parser.outports) {
      parser.outports = {};
    }

    if (!options.caseSensitive) {
      pub = pub.toLowerCase();
      port = port.toLowerCase();
    }

    parser.outports[pub] = {process:node, port:port};
  }

  parser.registerEdges = function (edges) {
    if (Array.isArray(edges)) {
      edges.forEach(function (o, i) {
        parser.edges.push(o);
      });
    }
  }

  parser.processEdges = function () {
    var flats, grouped;
    flats = flatten(parser.edges);
    grouped = [];
    var current = {};
    for (var i = 1; i < flats.length; i += 1) {
        // skip over default ports at the beginning of lines (could also handle this in grammar)
        if (("src" in flats[i - 1] || "data" in flats[i - 1]) && "tgt" in flats[i]) {
            flats[i - 1].tgt = flats[i].tgt;
            grouped.push(flats[i - 1]);
            i++;
        }
    }
    return grouped;
  }

  function makeName(s) {
    return s[0] + s[1].join("");
  }

  function makePort(process, port, defaultPort) {
    if (!options.caseSensitive) {
      defaultPort = defaultPort.toLowerCase()
    }
    var p = {
        process: process,
        port: port ? port.port : defaultPort
    };
    if (port && port.index != null) {
        p.index = port.index;
    }
    return p;
}

  function makeInPort(process, port) {
      return makePort(process, port, defaultInPort);
  }
  function makeOutPort(process, port) {
      return makePort(process, port, defaultOutPort);
  }
}

start
  = (line)*  { return parser.getResult();  }

line
//  = _ "INPORT=" node:node "." port:portName ":" pub:portName _ LineTerminator? {return parser.registerInports(node,port,pub)}
//  / _ "OUTPORT=" node:node "." port:portName ":" pub:portName _ LineTerminator? {return parser.registerOutports(node,port,pub)}
//  / _ "DEFAULT_INPORT=" name:portName _ LineTerminator? { defaultInPort = name}
//  / _ "DEFAULT_OUTPORT=" name:portName _ LineTerminator? { defaultOutPort = name}
//  / annotation:annotation newline { return parser.registerAnnotation(annotation[0], annotation[1]); }
  = comment newline?
  / _ newline
  / _ edges:connection _ LineTerminator? {return parser.registerEdges(edges);}

LineTerminator
  = _ ","? comment? newline?

newline
  = [\n\r\u2028\u2029]

comment
  = _ "#" (anychar)*

connection
  = x:source _ "->" _ y:connection { return [x,y]; }
  / destination

source
  = bridge
  / outport
  / iip

destination
  = inport
  / bridge

bridge
//  = x:port__ proc:node y:__port  { return [{"tgt":makeInPort(proc, x)},{"src":makeOutPort(proc, y)}]; }
//  / x:(port__)? proc:nodeWithComponent y:(__port)?  { return [{"tgt":makeInPort(proc, x)},{"src":makeOutPort(proc, y)}]; }
  = x:(port__)? proc:node y:(__port)?  { return [{"tgt":makeInPort(proc, x)},{"src":makeOutPort(proc, y)}]; }

outport
  = proc:node port:(__port)? { return {"src":makeOutPort(proc, port)} }

inport
  = port:(port__)? proc:node  { return {"tgt":makeInPort(proc, port)} }

iip
  = "'" iip:(iipchar)* "'"        { return {"data":iip.join("")} }
  / iip:JSON_text  { return {"data":iip} }

node
  = name:nodeNameAndComponent { return name}
  / name:nodeName { return name}
  / name:nodeComponent { return name}

nodeName
  = name:([a-zA-Z_][a-zA-Z0-9_\-]*) { return makeName(name)}

nodeNameAndComponent
  = name:nodeName comp:component { parser.addNode(name,comp); return name}

nodeComponent
  = comp:component { return parser.addAnonymousNode(comp, location().start.offset) }

nodeWithComponent
  = nodeNameAndComponent
  / nodeComponent

component
  = "(" comp:([a-zA-Z/\.@\-0-9_]*)? meta:compMeta? ")" { var o = {}; comp ? o.comp = comp.join("") : o.comp = ''; meta ? o.meta = meta : null; return o; }

compMeta
  = "," meta:JSON_text  {return meta}

annotation
  = "#" __ "@" key:[a-zA-Z0-9\-_]+ __ value:[a-zA-Z0-9\-_ \.]+ { return [key.join(''), value.join('')]; }

port
  = portname:portName portindex:(portIndex)? {return { port: options.caseSensitive? portname : portname.toLowerCase(), index: portindex != null ? portindex : undefined }}

port__
  = port:port __ { return port; }

__port
  = __ port:port { return port; }

portName
  = portname:([A-Z][A-Z.0-9_]*) {return makeName(portname)}

portIndex
  = "[" portindex:[0-9]+ "]" {return parseInt(portindex.join(''))}

anychar
  = [^\n\r\u2028\u2029]

iipchar
  = [\\]['] { return "'"; }
  / [^']

_
  = ([ \t]*)?

__
  = " "+

/*
 * JSON Grammar
 * ============
 *
 * Based on the grammar from RFC 7159 [1].
 *
 * Note that JSON is also specified in ECMA-262 [2], ECMA-404 [3], and on the
 * JSON website [4] (somewhat informally). The RFC seems the most authoritative
 * source, which is confirmed e.g. by [5].
 *
 * [1] http://tools.ietf.org/html/rfc7159
 * [2] http://www.ecma-international.org/publications/standards/Ecma-262.htm
 * [3] http://www.ecma-international.org/publications/standards/Ecma-404.htm
 * [4] http://json.org/
 * [5] https://www.tbray.org/ongoing/When/201x/2014/03/05/RFC7159-JSON
 */

/* ----- 2. JSON Grammar ----- */

JSON_text
    = ws value:value ws { return value; }

begin_array     = ws "[" ws
begin_object    = ws "{" ws
end_array       = ws "]" ws
end_object      = ws "}" ws
name_separator  = ws ":" ws
value_separator = ws "," ws

ws "whitespace" = [ \t\n\r]*

/* ----- 3. Values ----- */

value
    = false
    / null
    / true
    / object
    / array
    / number
    / string

false = "false" { return false; }
null  = "null"  { return null;  }
true  = "true"  { return true;  }

/* ----- 4. Objects ----- */

object
    = begin_object
      members:(
        head:member
        tail:(value_separator m:member { return m; })*
        {
          var result = {}, i;

          result[head.name] = head.value;

          for (i = 0; i < tail.length; i++) {
            result[tail[i].name] = tail[i].value;
          }

          return result;
        }
      )?
      end_object
      { return members !== null ? members: {}; }

member
    = name:string name_separator value:value {
        return { name: name, value: value };
      }

/* ----- 5. Arrays ----- */

array
    = begin_array
      values:(
        head:value
        tail:(value_separator v:value { return v; })*
        { return [head].concat(tail); }
      )?
      end_array
      { return values !== null ? values : []; }

/* ----- 6. Numbers ----- */

number "number"
    = minus? int frac? exp? { return parseFloat(text()); }

decimal_point = "."
digit1_9      = [1-9]
e             = [eE]
exp           = e (minus / plus)? DIGIT+
frac          = decimal_point DIGIT+
int           = zero / (digit1_9 DIGIT*)
minus         = "-"
plus          = "+"
zero          = "0"

/* ----- 7. Strings ----- */

string "string"
    = quotation_mark chars:char* quotation_mark { return chars.join(""); }

char
    = unescaped
    / escape
      sequence:(
          '"'
        / "\\"
        / "/"
        / "b" { return "\b"; }
        / "f" { return "\f"; }
        / "n" { return "\n"; }
        / "r" { return "\r"; }
        / "t" { return "\t"; }
        / "u" digits:$(HEXDIG HEXDIG HEXDIG HEXDIG) {
            return String.fromCharCode(parseInt(digits, 16));
          }
      )
      { return sequence; }

escape         = "\\"
quotation_mark = '"'
unescaped      = [^\0-\x1F\x22\x5C]

/* ----- Core ABNF Rules ----- */

/* See RFC 4234, Appendix B (http://tools.ietf.org/html/rfc4627). */
DIGIT  = [0-9]
HEXDIG = [0-9a-f]i