-------------------------------------------------------------------------------
--                                                                           --
--                                  Yolk                                     --
--                                                                           --
--                               View.Syndication                                  --
--                                                                           --
--                                  SPEC                                     --
--                                                                           --
--                   Copyright (C) 2010-2011, Thomas L�cke                   --
--                                                                           --
--  Yolk is free software;  you can  redistribute it  and/or modify it under --
--  terms of the  GNU General Public License as published  by the Free Soft- --
--  ware  Foundation;  either version 2,  or (at your option) any later ver- --
--  sion.  Yolk is distributed in the hope that it will be useful, but WITH- --
--  OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
--  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
--  for  more details.  You should have  received  a copy of the GNU General --
--  Public License  distributed with Yolk.  If not, write  to  the  Free     --
--  Software Foundation,  51  Franklin  Street,  Fifth  Floor, Boston,       --
--  MA 02110 - 1301, USA.                                                    --
--                                                                           --
-------------------------------------------------------------------------------

--  The syndication resource.

with Ada.Strings.Unbounded;
with AWS.Response;
with AWS.Status;
with Yolk.Cache.Discrete_Keys;
with Yolk.Syndication.Writer;

package View.Syndication is

   use Ada.Strings.Unbounded;
   use Yolk.Syndication.Writer;

   Feed : Atom_Feed := New_Atom_Feed (Base_URI    => "base",
                                      Language    => "lang",
                                      Max_Age     => 10.0,
                                      Min_Entries => 5,
                                      Max_Entries => 8);
   --  Declare a new Atom_Feed object.

   type Cache_Keys is (AFeed);

   package Atom_Cache is new Yolk.Cache.Discrete_Keys
     (Key_Type        => Cache_Keys,
      Element_Type    => Unbounded_String);
   --  Since it's very expensive to construct the Atom XML, we cache it, so we
   --  rebuild it if the cached version is older than one hour.

   function Generate
     (Request : in AWS.Status.Data)
      return AWS.Response.Data;
   --  Generate the content for the /syndication resource.

end View.Syndication;
