// Flow charts
function sequence(nodes) {
  var margin = {top: 20, right: 440, bottom: 0, left: 40},
      width = 960 - margin.right,
      height = 40 - margin.top - margin.bottom,
      step = 160;

  var svg = d3.select("body").append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .style("margin", "1em 0 1em " + -margin.left + "px");

  var g = svg.append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  var node = g.selectAll(".node")
      .data(nodes)
    .enter().append("g")
      .attr("class", function(d) { return (d.type || "") + " node"; })
      .attr("transform", function(d, i) { return "translate(" + i * step + ",0)"; });

  node.append("text")
      .attr("x", 6)
      .attr("dy", ".32em")
      .text(function(d) { return d.name; })
      .each(function(d) { d.width = d.name ? this.getComputedTextLength() + 12 : 0; });

  node.insert("rect", "text")
      .attr("ry", 6)
      .attr("rx", 6)
      .attr("y", -10)
      .attr("height", 20)
      .attr("width", function(d) { return d.width; });

  var link = g.selectAll(".link")
      .data(d3.range(nodes.length - 1))
    .enter().insert("g", ".node")
      .attr("class", function(i) {
        return (nodes[i + 1].type ? "to-" + nodes[i + 1].type + " " : " ")
          + (nodes[i].type ? "from-" + nodes[i].type + " " : " ")
          + " link";
      });

  link.append("path")
      .attr("d", function(i) { return "M" + (i * step + nodes[i].width) + ",0H" + ((i + 1) * step - 11); });

  link.append("text")
      .attr("x", function(i) { return (i + .5) * step + nodes[i].width / 2; })
      .attr("y", -6)
      .style("text-anchor", "middle")
      .text(function(i) { return nodes[i].link; });

  return svg;
}