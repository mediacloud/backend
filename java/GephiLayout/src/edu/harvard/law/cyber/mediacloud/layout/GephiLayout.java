/*
Copyright 2008-2010 Gephi
Authors : Mathieu Bastian <mathieu.bastian@gephi.org>
Website : http://www.gephi.org

This file is derived from the demos distributed with the Gephi Toolkit.

Gephi is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

Gephi is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Gephi.  If not, see <http://www.gnu.org/licenses/>.
*/
package edu.law.harvard.cyber.mediacloud.layout;

import java.awt.geom.Rectangle2D;
import java.awt.Rectangle;
import java.io.File;
import java.io.IOException;
import java.lang.reflect.Field;

import org.gephi.graph.api.DirectedGraph;
import org.gephi.graph.api.GraphController;
import org.gephi.graph.api.GraphModel;
import org.gephi.graph.api.Node;
import org.gephi.io.exporter.api.ExportController;
import org.gephi.io.exporter.plugin.ExporterGEXF;
import org.gephi.io.importer.api.Container;
import org.gephi.io.importer.api.EdgeDefault;
import org.gephi.io.importer.api.ImportController;
import org.gephi.io.processor.plugin.DefaultProcessor;
import org.gephi.layout.plugin.forceAtlas2.ForceAtlas2;
import org.gephi.layout.plugin.fruchterman.FruchtermanReingold;
import org.gephi.layout.plugin.force.StepDisplacement;
import org.gephi.layout.plugin.force.yifanHu.YifanHuLayout;
import org.gephi.layout.plugin.labelAdjust.LabelAdjust;
import org.gephi.project.api.ProjectController;
import org.gephi.project.api.Workspace;
import org.gephi.visualization.impl.TextDataImpl;
import org.gephi.visualization.impl.TextDataImpl.TextLine;
import org.openide.util.Lookup;


/**
    This program uses the gephi toolkit to layout a graph using gephi's force atlas 2 layout
*/
public class GephiLayout 
{

    public static void main(String[] args) 
    {
        if ( args.length < 2 )
        {
            System.err.println( "usage: java GephiLayout <import file name> <export file name>" );
            return;
        }
        
        File importFile = new File( args[0] );
        File exportFile = new File( args[1] );


        //Init a project - and therefore a workspace
        ProjectController pc = Lookup.getDefault().lookup( ProjectController.class) ;
        pc.newProject();
        Workspace workspace = pc.getCurrentWorkspace();

        ImportController importController = Lookup.getDefault().lookup( ImportController.class );

        //Import file       
        Container container;
        try 
        {
            container = importController.importFile( importFile );
            container.setAutoScale( false );
            // container.setDuplicateWithLabels( true );
            
            if ( container == null )
            {
                System.err.println( "Unable to import file: " + importFile );
                return;
            }
            
            container.getLoader().setEdgeDefault( EdgeDefault.DIRECTED );
        } 
        catch (Exception ex) 
        {
            ex.printStackTrace();
            return;
        }

        //Append imported data to GraphAPI
        importController.process( container, new DefaultProcessor(), workspace );

        GraphModel graphModel = Lookup.getDefault().lookup( GraphController.class ).getModel();
        DirectedGraph graph = graphModel.getDirectedGraph();
        
        System.out.println( "layout ...");

        // ForceAtlas2 layout = new ForceAtlas2( null );
        // layout.setGraphModel( graphModel );
        // layout.resetPropertiesValues();
        // layout.setGravity( new Double( graph.getNodeCount() ) );
        // layout.setScalingRatio( graph.getNodeCount() * 1.5 );
        // layout.setOutboundAttractionDistribution( true );
        // layout.setAdjustSizes( true );

        FruchtermanReingold layout = new FruchtermanReingold( null );
        layout.setGraphModel( graphModel );        
        layout.setArea( new Float( 10000 ) );
        layout.setGravity( 1.0 );
        layout.setSpeed( 1.0 );

        // StepDisplacement sd = new StepDisplacement( 20 );
        // 
        // YifanHuLayout layout = new YifanHuLayout( null, sd );
        // layout.setGraphModel( graphModel );
        // layout.setOptimalDistance( new Float( 10 ) );
        // layout.setRelativeStrength( new Float( 1 ) );

        layout.initAlgo();
        for ( int i = 0; i < 5000 && layout.canAlgo(); i++ ) 
        {
            layout.goAlgo();
        }
            
        try 
        {    
            for ( Node node: graphModel.getGraph().getNodes().toArray() )
            {
               TextDataImpl td = ( TextDataImpl ) node.getNodeData().getTextData();
               String labelText = node.getNodeData().getLabel();
               td.setText( labelText );
               //Could perhaps used getFontMetrics here to be more accurate but
               // this heuristic seems to work for me:
               Rectangle2D bounds=new Rectangle(labelText.length()*10,10);
               //Use reflection to set the protected Bounds data to non-zero sizes.
               Field protectedLineField = TextDataImpl.class.getDeclaredField( "line" );
               protectedLineField.setAccessible(true);        
               TextLine line = (TextLine) protectedLineField.get(td);
               line.setBounds(bounds);
            }
        }
        catch (Exception ex) 
        {
            ex.printStackTrace();
            return;
        }


        LabelAdjust labelAdjust = new LabelAdjust( null );
        labelAdjust.setGraphModel( graphModel );
        labelAdjust.setAdjustBySize( true );
        
        labelAdjust.initAlgo();
        for ( int i = 0; i < 5000 && labelAdjust.canAlgo(); i++ ) 
        {
            labelAdjust.goAlgo();
        }
        
        ExportController ec = Lookup.getDefault().lookup( ExportController.class );
        ExporterGEXF exporter = (ExporterGEXF) ec.getExporter("gexf");
        exporter.setExportDynamic( false );
        exporter.setWorkspace( workspace );
        try 
        {
            System.out.println( "export ..." );
            ec.exportFile( exportFile, exporter );
        } 
        catch (IOException ex) 
        {
            ex.printStackTrace();
            return;
        }
        
        System.exit( 0 );
    }
}
