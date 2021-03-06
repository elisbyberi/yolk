-------------------------------------------------------------------------------
--                                                                           --
--                   Copyright (C) 2010-, Thomas Løcke                   --
--                                                                           --
--  This library is free software;  you can redistribute it and/or modify    --
--  it under terms of the  GNU General Public License  as published by the   --
--  Free Software  Foundation;  either version 3,  or (at your  option) any  --
--  later version. This library is distributed in the hope that it will be   --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of  --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                     --
--                                                                           --
--  As a special exception under Section 7 of GPL version 3, you are         --
--  granted additional permissions described in the GCC Runtime Library      --
--  Exception, version 3.1, as published by the Free Software Foundation.    --
--                                                                           --
--  You should have received a copy of the GNU General Public License and    --
--  a copy of the GCC Runtime Library Exception along with this program;     --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
--  <http://www.gnu.org/licenses/>.                                          --
--                                                                           --
-------------------------------------------------------------------------------

package Yolk is

   Default_Config_File : constant String := "configuration/config.ini";
   Version             : constant String := "0.83";

   function PID_File
     return String;
   --  Return the name and location of the application PID file given with the
   --  --pid-file commandline parameter. If --pid-file is not set then return
   --  an empty string.

   function Yolk_Config_File
     return String;
   --  Return the name and location of the configuration file given with the
   --  --yolk-config-file commandline parameter. If --yolk-config-file is not
   --  set then return Default_Config_File.

end Yolk;
