/* PostRawComputeTest performs data quality checks after the 
 * ensembl raw compute.
 *    
 * Copyright (C) 2002 Craig Melsopp
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA */

package org.ensembl.dataquality;

import java.sql.*;
import junit.framework.*; 
import java.io.*;
import java.util.*;
import gnu.getopt.*;


/**
 * Class containing several data quality checks for the post raw compute data
 * set. It is implemented using the <a href="http://junit.org">junit</a>
 * framework.
 *
 * <p>This is <i>currently</i> a framework implementation containing only a
 * couple of real data quality tests. Alistair Rust will flesh out with
 * additional tests in the near future. This class can be used as the basis
 * for other data quality control tests.
 *
 * <p>usage: 
 *
 * <ol>
 *
 * <li>Ensure <a href="http://junit.org">junit</a> and <a
href="http://www.urbanophile.com/arenn/">getopt</a> classes are available on
your classpath.
 *
 *    <li>Specify necessary parameters in the configuration file
 * <b>data_quality.conf</b> in the current working directory. e.g.

   <pre>
   jdbc.database = alistair_mouse_wi_Feb02
   jdbc.port = 3307
   jdbc.host = 127.0.0.1
   jdbc.user = ensro
   jdbc.password = 
   </pre>

 * This file can be omitted if all the parameters are provided on the command
 * line when running the class directly.
 *
 * <li>Start the tests by one of these methods:
 * <ul>
 *
 *   <li><b>java org.ensembl.dataquality.PostRawComputeTest <-h HOST > <-P
 *   PORT> <-u USERNAME> <-p PASSWORD> < testMETHOD_1 testMETHOD_2 *
 *   ... ></b> 
 * 
 *   <br>The -h, -P, -u and -p parameters override corresponding settings in
 *   the configuration file. If any testMETHODs are specified then those
 *   specific methods are run instead of the whole set.
 *
 *   <li><b>java junit.swingui.TestRunner
 *   org.ensembl.dataquality.PostRawComputeTest</b>
 *
 *    <br>Runs all tests using a the * standard junit graphical user *
 *    interface.)
 *
 *   <li>Run from apache <a href="http://jakarta.apache.org/ant/">ant</a>. 
 *
 * </ul>
 * </ol>
 *
 * @author <a href="craig@ebi.ac.uk">Craig Melsopp</a>
 * @version $Revision$ */

public class PostRawComputeTest extends TestCase{

  private static String database = null;
  private static String port = null;
  private static String host = null;
  private static String user = null;
  private static String password = null;
  private static String connectionString = null;
  
  public static final void main(String[] args) {

    Getopt g = new Getopt("PostRawComputeTest", args, "h:P:u:p:");

    int c;
    while ((c = g.getopt()) != -1)
      {
        switch(c)
          {
          case 'h':         
            host = g.getOptarg();
            break;

          case 'P':         
            port = g.getOptarg();
            break;

          case 'u':         
            user = g.getOptarg();
            break;

          case 'p':         
            password = g.getOptarg();
            break;
          }
      }
 
    

    if (g.getOptind()==args.length) {
      // Run all tests
      junit.textui.TestRunner.run(new TestSuite(PostRawComputeTest.class));
    }
    else {
      // Run tests specified on command line.
      for(int i=g.getOptind(); i<args.length; ++i) {
        junit.textui.TestRunner.run(new PostRawComputeTest(args[i]));
      }
    }

  }

  public PostRawComputeTest(String name){
    super(name);
  }
  

  protected void setUp() throws Exception {

    // Load configuration values from file. If command line parameters where
    // provided then they override those in the file.
    File configFile = new File("data_quality.conf");
    if ( configFile.exists() ) {
      FileInputStream configFileStream = new FileInputStream(configFile);
      Properties config = new Properties();
      config.load(configFileStream);
      configFileStream.close();
      
      if ( database==null) database = config.getProperty("jdbc.database");
      if ( port==null) port = config.getProperty("jdbc.port"); 
      if ( host==null) host = config.getProperty("jdbc.host"); 
      if ( user==null) user = config.getProperty("jdbc.user"); 
      if ( password==null) password = config.getProperty("jdbc.password"); 
    }
    else {
      if (database==null
          || port==null
          || host==null
          || user==null) {
        System.err.println("Warning: configuration file not exist " 
                           + configFile.getName());
      }
      
    }
    

    // Load db driver
    Class.forName("org.gjt.mm.mysql.Driver").newInstance();

    connectionString = "jdbc:mysql://" 
      + host 
      + ((port!=null)? ":"+port:"") 
      + "/" + database;
    
    System.out.println("Connection string = " + connectionString);



  }



  /**
   * @param sql SQL to execute
   * @return result set returned byte executing SQL.
   */
  private ResultSet execute(String sql) throws Exception {

    Connection conn =
      DriverManager.getConnection(connectionString
                                  ,user
                                  ,password );
    System.out.println("Executing sql : " + sql);
    return conn.createStatement().executeQuery(sql);
  }



  /**
   * Convenience method; executes the SQL query and writes any results to the file.
   *
   * @param sql SQL query to execute
   * @param resultsFile file to dump result set into (optional, set to null
   * if not needed).
   * @param expectResults whether results are expected
   * @return null if executing the SQL produces _expectedResults_,
   * otherwise returns an error message.  */
  private String runSQL(String sql,
                        String resultsFile,
                        boolean expectResults) throws Exception {

    ResultSet rs = execute(sql);

    if (rs.next()) {
      // We found at least one row int the database corresponding to the
      // query...

      if ( resultsFile!=null ) {
        // Write result set to file in tab separated format.
        System.out.println("Writing file : " + resultsFile);
        OutputStreamWriter os = new OutputStreamWriter(new FileOutputStream(resultsFile));
        int lineCount = 0;
        final int nColumns= rs.getMetaData().getColumnCount();
        do {
          for(int i=1; i<=nColumns; ++i) {
            os.write(rs.getString(i));
            if (i<nColumns) os.write("\t");
            os.write("\n");
          }
          lineCount++;
        } while (rs.next());
        os.close();
      }
      
      if ( expectResults ) {
        return null;
      }
      else {
        return "Results written to " + resultsFile;
      }
      }
    
    if ( expectResults ) {
      return "No items found matching :" + sql;
    }
    else {
      return null;
    }
  }


  /**
   * Quick db connection test.
   */
  public void testCheck() throws Exception {
    String errorMessage = runSQL("show tables"
                                 ,null
                                 ,true);
    assertNull(errorMessage, errorMessage);
    
  }

  
  public void testStartBeforeEnd() throws Exception {
    String errorMessage = runSQL("select * from feature where seq_start > seq_end"
                                 ,"seq_start_greater_than_seq_end.txt",
                                 false);
    assertNull(errorMessage, errorMessage);
  }


  public void testHStartBeforeHEnd() throws Exception {
    String errorMessage = runSQL("select * from feature where hstart > hend"
                                 ,"hstart_greater_than_hend.txt",
                                 false);
    assertNull(errorMessage, errorMessage);
  }





} // PostRawComputeTest
