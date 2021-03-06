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

with Ada.Calendar;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with AWS.MIME;
with ZLib;
with Yolk.Configuration;
with Yolk.Not_Found;
with Yolk.Log;

package body Yolk.Static_Content is

   protected GZip_And_Cache is
      procedure Do_It
        (GZ_Resource : in String;
         Resource    : in String);
      --  If a compressable resource is requested and it doesn't yet exist,
      --  then this procedure takes care of GZip'ing the Resource and saving
      --  it to disk as a .gz file.

      function Get_Cache_Option
        return AWS.Messages.Cache_Option;
      --  Return the Cache_Option object for the resource.

      procedure Initialize;
      --  Delete and re-create the Compressed_Cache_Directory.

      procedure Set_Cache_Options
        (No_Cache         : in Boolean := False;
         No_Store         : in Boolean := False;
         No_Transform     : in Boolean := False;
         Max_Age          : in AWS.Messages.Delta_Seconds := 86400;
         S_Max_Age        : in AWS.Messages.Delta_Seconds :=
           AWS.Messages.Unset;
         Public           : in Boolean := False;
         Must_Revalidate  : in Boolean := True;
         Proxy_Revalidate : in Boolean := False);
      --  Set the Cache_Data objects.
   private
      Cache_Options : Ada.Strings.Unbounded.Unbounded_String;
   end GZip_And_Cache;
   --  Handle GZip'ing, saving and deletion of compressable resources. This is
   --  done in a protected object so we don't get multiple threads all trying
   --  to save/delete the same resources at the same time.

   function Good_Age
     (Resource : in String)
      return Boolean;
   --  Return True if the age of Resource is younger than the configuration
   --  parameter Compressed_Max_Age. If Compressed_Max_Age is 0, then always
   --  return True.

   --------------------
   --  Compressable  --
   --------------------

   function Compressable
     (Request : in AWS.Status.Data)
      return AWS.Response.Data
   is
      use Ada.Directories;
      use AWS.Messages;
      use AWS.Status;
      use Yolk.Configuration;
      use Yolk.Log;

      GZ_Resource : constant String :=
                      Config.Get (Compressed_Static_Content_Cache)
                      & URI (Request) & ".gz";
      --  The path to the GZipped resource.

      Resource    : constant String := Config.Get (WWW_Root) & URI (Request);
      --  The path to the requested resource.

      MIME_Type         : constant String := AWS.MIME.Content_Type (Resource);
      Minimum_File_Size : constant File_Size :=
                            File_Size (Integer'(Config.Get
                              (Compress_Static_Content_Minimum_File_Size)));
   begin
      if not Exists (Resource)
        or else Kind (Resource) /= Ordinary_File
      then
         return Yolk.Not_Found.Generate (Request);
      end if;

      if Is_Supported (Request, GZip) then
         if Exists (GZ_Resource)
           and then Kind (GZ_Resource) = Ordinary_File
         then
            if Good_Age (Resource => GZ_Resource) then
               return AWS.Response.File
                 (Content_Type  => MIME_Type,
                  Filename      => GZ_Resource,
                  Encoding      => GZip,
                  Cache_Control => GZip_And_Cache.Get_Cache_Option);
            else
               Delete_File (GZ_Resource);
            end if;
         elsif Exists (GZ_Resource)
           and then Kind (GZ_Resource) /= Ordinary_File
         then
            --  Not so good. Log to ERROR trace and return un-compressed
            --  content.
            Trace
              (Handle  => Error,
               Message => GZ_Resource
               & " exists and is not an ordinary file");

            return AWS.Response.File
              (Content_Type  => MIME_Type,
               Filename      => Resource,
               Cache_Control => GZip_And_Cache.Get_Cache_Option);
         end if;

         if Size (Resource) > Minimum_File_Size then
            GZip_And_Cache.Do_It (GZ_Resource => GZ_Resource,
                                  Resource    => Resource);

            return AWS.Response.File
              (Content_Type  => MIME_Type,
               Filename      => GZ_Resource,
               Encoding      => GZip,
               Cache_Control => GZip_And_Cache.Get_Cache_Option);
         end if;
      end if;

      return AWS.Response.File
        (Content_Type  => MIME_Type,
         Filename      => Resource,
         Cache_Control => GZip_And_Cache.Get_Cache_Option);
   end Compressable;

   ----------------
   --  Good_Age  --
   ----------------

   function Good_Age
     (Resource : in String)
      return Boolean
   is
      use Ada.Calendar;
      use Ada.Directories;
      use Yolk.Configuration;

      Max_Age : constant Natural :=
                  Config.Get (Compressed_Static_Content_Max_Age);
   begin
      if Max_Age = 0 then
         return True;
      end if;

      if
        Clock - Modification_Time (Resource) > Duration (Max_Age)
      then
         return False;
      end if;

      return True;
   end Good_Age;

   ----------------------
   --  GZip_And_Cache  --
   ----------------------

   protected body GZip_And_Cache is
      procedure Do_It
        (GZ_Resource : in String;
         Resource    : in String)
      is
         use Ada.Directories;

         Cache_Dir : constant String := Containing_Directory (GZ_Resource);
      begin
         if Exists (GZ_Resource) then
            return;
            --  We only need to continue if the GZ_Resource doesn't exist. It
            --  might not have existed when Do_It was called, but the previous
            --  Do_It call might've created it. So if it now exists, we simply
            --  return.
         end if;

         if not Exists (Cache_Dir) then
            Create_Path (Cache_Dir);
         end if;

         Compress_File :
         declare
            File_In  : Ada.Streams.Stream_IO.File_Type;
            File_Out : Ada.Streams.Stream_IO.File_Type;
            Filter   : ZLib.Filter_Type;

            procedure Data_Read
              (Item : out Ada.Streams.Stream_Element_Array;
               Last : out Ada.Streams.Stream_Element_Offset);
            --  Read data from File_In.

            procedure Data_Write
              (Item : in Ada.Streams.Stream_Element_Array);
            --  Write data to File_Out.

            procedure Translate is new ZLib.Generic_Translate
              (Data_In  => Data_Read,
               Data_Out => Data_Write);
            --  Do the actual compression. Use Data_Read to read from File_In
            --  and Data_Write to write the compressed content to File_Out.

            -----------------
            --  Data_Read  --
            -----------------

            procedure Data_Read
              (Item : out Ada.Streams.Stream_Element_Array;
               Last : out Ada.Streams.Stream_Element_Offset)
            is
            begin
               Ada.Streams.Stream_IO.Read
                 (File => File_In,
                  Item => Item,
                  Last => Last);
            end Data_Read;

            ----------------
            --  Data_Out  --
            ----------------

            procedure Data_Write
              (Item : in Ada.Streams.Stream_Element_Array)
            is
            begin
               Ada.Streams.Stream_IO.Write (File => File_Out,
                                            Item => Item);
            end Data_Write;
         begin
            Ada.Streams.Stream_IO.Open
              (File => File_In,
               Mode => Ada.Streams.Stream_IO.In_File,
               Name => Resource);

            Ada.Streams.Stream_IO.Create
              (File => File_Out,
               Mode => Ada.Streams.Stream_IO.Out_File,
               Name => GZ_Resource);

            ZLib.Deflate_Init
              (Filter => Filter,
               Level  => ZLib.Best_Compression,
               Header => ZLib.GZip);

            Translate (Filter);

            ZLib.Close (Filter);

            Ada.Streams.Stream_IO.Close (File => File_In);
            Ada.Streams.Stream_IO.Close (File => File_Out);
         end Compress_File;
      end Do_It;

      ------------------------
      --  Get_Cache_Option  --
      ------------------------

      function Get_Cache_Option
        return AWS.Messages.Cache_Option
      is
         use Ada.Strings.Unbounded;
      begin
         return AWS.Messages.Cache_Option (To_String (Cache_Options));
      end Get_Cache_Option;

      ------------------
      --  Initialize  --
      ------------------

      procedure Initialize
      is
         use Ada.Directories;
         use Yolk.Configuration;
         use Yolk.Log;
      begin
         if Exists (Config.Get (Compressed_Static_Content_Cache))
           and then
             Kind (Config.Get (Compressed_Static_Content_Cache)) = Directory
         then
            Delete_Tree
              (Directory => Config.Get (Compressed_Static_Content_Cache));

            Trace (Info,
                   Config.Get (Compressed_Static_Content_Cache)
                   & " found and deleted");
         end if;

         Create_Path
           (New_Directory => Config.Get (Compressed_Static_Content_Cache));

         Trace (Info,
                Config.Get (Compressed_Static_Content_Cache)
                & " created");
      end Initialize;

      -------------------------
      --  Set_Cache_Options  --
      -------------------------

      procedure Set_Cache_Options
        (No_Cache         : in Boolean := False;
         No_Store         : in Boolean := False;
         No_Transform     : in Boolean := False;
         Max_Age          : in AWS.Messages.Delta_Seconds := 86400;
         S_Max_Age        : in AWS.Messages.Delta_Seconds :=
           AWS.Messages.Unset;
         Public           : in Boolean := False;
         Must_Revalidate  : in Boolean := True;
         Proxy_Revalidate : in Boolean := False)
      is
         use Ada.Strings.Unbounded;

         Cache_Data : AWS.Messages.Cache_Data (CKind => AWS.Messages.Response);
      begin
         Cache_Data.No_Cache         := No_Cache;
         Cache_Data.No_Store         := No_Store;
         Cache_Data.No_Transform     := No_Transform;
         Cache_Data.Max_Age          := Max_Age;
         Cache_Data.S_Max_Age        := S_Max_Age;
         Cache_Data.Public           := Public;
         Cache_Data.Must_Revalidate  := Must_Revalidate;
         Cache_Data.Proxy_Revalidate := Proxy_Revalidate;

         Cache_Options := To_Unbounded_String
           (String (AWS.Messages.To_Cache_Option (Cache_Data)));
      end Set_Cache_Options;
   end GZip_And_Cache;

   ------------------------
   --  Non_Compressable  --
   ------------------------

   function Non_Compressable
     (Request : in AWS.Status.Data)
      return AWS.Response.Data
   is
      use Ada.Directories;
      use AWS.MIME;
      use AWS.Status;
      use Yolk.Configuration;

      Resource : constant String := Config.Get (WWW_Root) & URI (Request);
      --  The path to the requested resource.
   begin
      if not Exists (Resource)
        or else Kind (Resource) /= Ordinary_File
      then
         return Yolk.Not_Found.Generate (Request);
      end if;

      return AWS.Response.File
        (Content_Type  => Content_Type (Resource),
         Filename      => Resource,
         Cache_Control => GZip_And_Cache.Get_Cache_Option);
   end Non_Compressable;

   -------------------------
   --  Set_Cache_Options  --
   -------------------------

   procedure Set_Cache_Options
     (No_Cache          : in Boolean := False;
      No_Store          : in Boolean := False;
      No_Transform      : in Boolean := False;
      Max_Age           : in AWS.Messages.Delta_Seconds := 86400;
      S_Max_Age         : in AWS.Messages.Delta_Seconds := AWS.Messages.Unset;
      Public            : in Boolean := False;
      Must_Revalidate   : in Boolean := True;
      Proxy_Revalidate  : in Boolean := False)
   is
   begin
      GZip_And_Cache.Set_Cache_Options
        (No_Cache         => No_Cache,
         No_Store         => No_Store,
         No_Transform     => No_Transform,
         Max_Age          => Max_Age,
         S_Max_Age        => S_Max_Age,
         Public           => Public,
         Must_Revalidate  => Must_Revalidate,
         Proxy_Revalidate => Proxy_Revalidate);
   end Set_Cache_Options;

   ----------------------------------
   --  Static_Content_Cache_Setup  --
   ----------------------------------

   procedure Static_Content_Cache_Setup
     (No_Cache          : in Boolean := False;
      No_Store          : in Boolean := False;
      No_Transform      : in Boolean := False;
      Max_Age           : in AWS.Messages.Delta_Seconds := 86400;
      S_Max_Age         : in AWS.Messages.Delta_Seconds := AWS.Messages.Unset;
      Public            : in Boolean := False;
      Must_Revalidate   : in Boolean := True;
      Proxy_Revalidate  : in Boolean := False)
   is
      use AWS.Messages;
   begin
      GZip_And_Cache.Initialize;

      GZip_And_Cache.Set_Cache_Options
        (No_Cache         => No_Cache,
         No_Store         => No_Store,
         No_Transform     => No_Transform,
         Max_Age          => Max_Age,
         S_Max_Age        => S_Max_Age,
         Public           => Public,
         Must_Revalidate  => Must_Revalidate,
         Proxy_Revalidate => Proxy_Revalidate);
   end Static_Content_Cache_Setup;

end Yolk.Static_Content;
