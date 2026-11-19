package com.xlib.txtreader;

import static org.junit.Assert.*;
import java.io.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.zip.*;
import org.json.*;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;

public class ComicArchiveTest {
    @Rule public TemporaryFolder folder=new TemporaryFolder();
    File zip(List<String> paths,Charset charset)throws Exception {
        File file=folder.newFile();
        try(ZipOutputStream out=new ZipOutputStream(new FileOutputStream(file),charset)){
            for(String path:paths){out.putNextEntry(new ZipEntry(path));out.write(path.getBytes(StandardCharsets.UTF_8));out.closeEntry();}
        }
        return file;
    }
    private static void patch(File file,int signature,int offset,int value,int bytes)throws Exception {
        byte[] data=Files.readAllBytes(file.toPath());
        for(int i=0;i<=data.length-4;i++)if((data[i]&255)==(signature&255)&&(data[i+1]&255)==((signature>>>8)&255)&&(data[i+2]&255)==((signature>>>16)&255)&&(data[i+3]&255)==((signature>>>24)&255)){
            for(int j=0;j<bytes;j++)data[i+offset+j]=(byte)(value>>>(8*j));Files.write(file.toPath(),data);return;
        }
        fail("Missing ZIP test header");
    }
    @Test public void consumesCurrentSharedPageOrderAndCanonicalUnicodeVectors()throws Exception {
        JSONObject vector;
        try(InputStream input=getClass().getClassLoader().getResourceAsStream("documents/comic-order-v1.json")){assertNotNull(input);vector=new JSONObject(new String(input.readAllBytes(),StandardCharsets.UTF_8));}
        List<String> paths=new ArrayList<>();JSONArray entries=vector.getJSONArray("entries");
        for(int i=0;i<entries.length();i++)paths.add(entries.getJSONObject(i).getString("path"));
        File file=zip(paths,StandardCharsets.UTF_8);
        try(ComicArchive archive=new ComicArchive(file,ComicArchive.NEVER)){
            List<ComicArchive.Entry> pages=archive.pages();JSONArray expected=vector.getJSONArray("pages");assertEquals(expected.length(),pages.size());
            for(int i=0;i<pages.size();i++)assertEquals(expected.getJSONObject(i).getString("canonicalPath"),pages.get(i).name);
        }
        Collections.reverse(paths);
        try(ComicArchive archive=new ComicArchive(zip(paths,StandardCharsets.UTF_8),ComicArchive.NEVER)){
            JSONArray expected=vector.getJSONArray("pages");for(int i=0;i<expected.length();i++)assertEquals(expected.getJSONObject(i).getString("canonicalPath"),archive.pages().get(i).name);
        }
    }
    @Test public void cp437NamesAreLosslessOnAllAndroidVersionsAndCrcRoundTrips()throws Exception {
        try(ComicArchive archive=new ComicArchive(zip(List.of("é2.png","é10.png"),Charset.forName("CP437")),ComicArchive.NEVER)){
            assertEquals("é2.png",archive.pages().get(0).name);
            ByteArrayOutputStream out=new ByteArrayOutputStream();archive.copy(archive.pages().get(1),out,ComicArchive.NEVER);
            assertEquals("é10.png",out.toString(StandardCharsets.UTF_8));
        }
    }
    @Test public void duplicateNfcPathsUnsafePathsAndHiddenDuplicatesRejectBeforeFiltering()throws Exception {
        for(List<String> paths:List.of(List.of("é.png","e\u0301.png"),List.of("../x.png"),List.of("/x.png"),List.of("C:/x.png"),List.of("a//x.png"),List.of("a/./x.png"),List.of("a\\x.png"),List.of("a/\u0085x.png"),List.of("dir/","dir"))){
            File file=zip(paths,StandardCharsets.UTF_8);assertThrows(paths.toString(),IOException.class,()->new ComicArchive(file,ComicArchive.NEVER));
        }
    }
    @Test public void unsupportedVisibleImagesAndEmptyArchivesDoNotSilentlyLosePages()throws Exception {
        for(List<String> paths:List.of(List.of("1.png","2.webp"),List.of("1.png","2.svg"),List.of("README.txt"),List.of(".hidden/1.png"))){
            try(ComicArchive archive=new ComicArchive(zip(paths,StandardCharsets.UTF_8),ComicArchive.NEVER)){assertThrows(IOException.class,archive::pages);}
        }
        try(ComicArchive archive=new ComicArchive(zip(List.of(".hidden/2.webp","1.png"),StandardCharsets.UTF_8),ComicArchive.NEVER)){assertEquals(1,archive.pages().size());}
    }
    @Test public void encryptedVolumesLinksMethodsAndOversizedEntriesRejectWithoutExtracting()throws Exception {
        int[][] cases={{8,1,2},{10,99,2},{24,129*1024*1024,4},{34,1,2},{4,3<<8,2}};
        for(int[] change:cases){File file=zip(List.of("1.png"),StandardCharsets.UTF_8);patch(file,0x02014b50,change[0],change[1],change[2]);if(change[0]==4)patch(file,0x02014b50,38,0120000<<16,4);assertThrows(IOException.class,()->new ComicArchive(file,ComicArchive.NEVER));}
    }
    @Test public void corruptedCrcAndLocalHeaderMismatchFailWithoutChangingSource()throws Exception {
        for(int[] change:new int[][]{{0x02014b50,16,123},{0x04034b50,8,0}}){
            File file=zip(List.of("1.png"),StandardCharsets.UTF_8);patch(file,change[0],change[1],change[2],change[1]==16?4:2);byte[] before=Files.readAllBytes(file.toPath());
            try(ComicArchive archive=new ComicArchive(file,ComicArchive.NEVER)){assertThrows(IOException.class,()->archive.copy(archive.pages().get(0),new ByteArrayOutputStream(),ComicArchive.NEVER));}
            assertArrayEquals(before,Files.readAllBytes(file.toPath()));
        }
    }
    @Test public void cancellationStopsDirectoryAndPageExpansion()throws Exception {
        File file=zip(List.of("1.png","2.png"),StandardCharsets.UTF_8);
        assertThrows(IOException.class,()->new ComicArchive(file,()->true));
        try(ComicArchive archive=new ComicArchive(file,ComicArchive.NEVER)){assertThrows(IOException.class,()->archive.copy(archive.pages().get(0),new ByteArrayOutputStream(),()->true));}
    }
    @Test public void diskBudgetCountsAbandonedPreviewCopiesBeforePreparingAnotherPage()throws Exception {
        File root=folder.newFolder("comic-previews"),old=new File(root,"old"),session=new File(root,"current");assertTrue(old.mkdir());assertTrue(session.mkdir());
        try(RandomAccessFile file=new RandomAccessFile(new File(old,"source.cbz"),"rw")){file.setLength(ComicArchive.MAX_SOURCE);}
        assertThrows(IOException.class,()->ComicPreviewFiles.reserve(session,1));assertFalse(new File(session,"page.tmp").exists());
    }
    @Test public void unicodePathExtraFieldOverridesCp437ButRejectsConflict()throws Exception {
        File file=folder.newFile();byte[] raw="page.png".getBytes(StandardCharsets.US_ASCII),unicode="第1.png".getBytes(StandardCharsets.UTF_8);CRC32 crc=new CRC32();crc.update(raw);
        byte[] extra=new byte[9+unicode.length];extra[0]=0x75;extra[1]=0x70;extra[2]=(byte)(5+unicode.length);extra[4]=1;
        for(int i=0;i<4;i++)extra[5+i]=(byte)(crc.getValue()>>>(8*i));System.arraycopy(unicode,0,extra,9,unicode.length);
        try(ZipOutputStream out=new ZipOutputStream(new FileOutputStream(file),Charset.forName("CP437"))){ZipEntry entry=new ZipEntry("page.png");entry.setExtra(extra);out.putNextEntry(entry);out.write(1);out.closeEntry();}
        try(ComicArchive archive=new ComicArchive(file,ComicArchive.NEVER)){assertEquals("第1.png",archive.pages().get(0).name);}
        patch(file,0x02014b50,8,2048,2);assertThrows(IOException.class,()->new ComicArchive(file,ComicArchive.NEVER));
    }
}
