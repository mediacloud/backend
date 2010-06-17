// This file contains the weighted network of coappearances of characters in
// Victor Hugo's novel "Les Miserables". Nodes represent characters as indicated
// by the labels, and edges connect any pair of characters that appear in the
// same chapter of the book. The values on the edges are the number of such
// coappearances. The data on coappearances were taken from D. E. Knuth, The
// Stanford GraphBase: A Platform for Combinatorial Computing, Addison-Wesley,
// Reading, MA (1993).
//
// The group labels were transcribed from "Finding and evaluating community
// structure in networks" by M. E. J. Newman and M. Girvan.

var miserables = {
  nodes:[
    {nodeName:"New York Times", group:1},
    {nodeName:"AP Online", group:2},
    {nodeName:"WSJ", group:2},
    {nodeName:"CNN", group:3},
    {nodeName:"Fox News", group:1}
  ],
  links:[
    {source:1, target:0, value:1},
    {source:2, target:0, value:8},
    {source:3, target:0, value:10},
    {source:3, target:2, value:6},
    {source:4, target:0, value:1}
  ]
};
