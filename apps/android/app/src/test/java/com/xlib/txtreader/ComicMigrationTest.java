package com.xlib.txtreader;

import static org.junit.Assert.*;
import android.content.*;
import android.database.*;
import android.database.sqlite.*;
import java.io.*;
import java.nio.file.Files;
import java.util.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class) @Config(sdk=35)
public class ComicMigrationTest {
    Context context;SharedPreferences prefs;LocalDatabase db;
    @Before public void setup(){context=RuntimeEnvironment.getApplication();context.deleteDatabase("xlib.db");prefs=context.getSharedPreferences("comic-migration",0);prefs.edit().clear().commit();}
    @After public void close(){if(db!=null)db.close();context.deleteDatabase("xlib.db");}
    Book book(long id,String format)throws Exception {File root=new File(context.getFilesDir(),"books");root.mkdirs();File file=new File(root,id+"-fixture."+format);Files.write(file.toPath(),new byte[]{1,2,3,4});Book b=new Book();b.id=id;b.format=format;b.path=file.getPath();b.title=b.sourceName="fixture."+format;b.author="author";b.encoding="UTF-8";b.fileSize=4;b.offset=2;b.updatedAt=123;b.pageMode=true;return b;}
    void seedV3()throws Exception {
        db=LocalDatabase.open(context,prefs);Book txt=book(1,"txt"),pdf=book(2,"pdf"),epub=book(3,"epub");assertTrue(db.saveBooks(Arrays.asList(txt,pdf,epub),null,0,0));assertTrue(db.addBookmark(1,2));
        db.saveDocumentPosition(pdf,DocumentLocator.pdf(1,4,.2),"ab".repeat(32),456);db.addDocumentBookmark(2,pdf.locator);
        db.saveDocumentPosition(epub,DocumentLocator.epub("OPS/a.xhtml",1,3,5,20),"cd".repeat(32),789);db.addDocumentBookmark(3,epub.locator);
        new ReadingPreferences(db).setReadingFontSize(23);db.putSyncValue("sync_configured_email","test@example.com");prefs.edit().putString("sync_token_ciphertext","protected-credential").commit();db.close();db=null;
        try(SQLiteDatabase raw=SQLiteDatabase.openDatabase(context.getDatabasePath("xlib.db").getPath(),null,SQLiteDatabase.OPEN_READWRITE)){
            raw.setForeignKeyConstraintsEnabled(false);
            for(String table:new String[]{"document_positions","document_bookmarks"})for(String column:new String[]{"profile","manifest_hash","page_key"})raw.execSQL("alter table "+table+" drop column "+column);
            raw.execSQL("pragma user_version=3");
        }
    }
    String rows(SQLiteDatabase raw,String table,String columns){StringBuilder values=new StringBuilder();try(Cursor c=raw.rawQuery("select "+columns+" from "+table+" order by 1",null)){while(c.moveToNext()){for(int i=0;i<c.getColumnCount();i++)values.append(c.isNull(i)?"<null>":c.getString(i)).append('|');values.append('\n');}}return values.toString();}
    @Test public void v3MigrationPreservesEveryOldValueAndCascadesOnlyTheDeletedBook()throws Exception {
        seedV3();Map<String,String> before=new LinkedHashMap<>();String[] tables={"books","reading_progress","book_preferences","bookmarks","toc_documents","toc_entries","settings","sync_configuration","book_hash_cache","remote_progress_cache","pending_file_deletions","legacy_migrations","legacy_cleanup","document_positions","document_bookmarks"};Map<String,String> columns=new HashMap<>();
        try(SQLiteDatabase raw=SQLiteDatabase.openDatabase(context.getDatabasePath("xlib.db").getPath(),null,SQLiteDatabase.OPEN_READWRITE)){for(String table:tables){StringBuilder names=new StringBuilder();try(Cursor c=raw.rawQuery("pragma table_info("+table+")",null)){while(c.moveToNext()){if(names.length()>0)names.append(',');names.append(c.getString(1));}}columns.put(table,names.toString());before.put(table,rows(raw,table,names.toString()));}}
        db=LocalDatabase.open(context,prefs);assertEquals(5,db.getReadableDatabase().getVersion());for(String table:tables)assertEquals(table,before.get(table),rows(db.getReadableDatabase(),table,columns.get(table)));assertEquals("protected-credential",prefs.getString("sync_token_ciphertext",null));
        Book comic=book(4,"cbr");List<Book> books=db.loadBooks();books.add(comic);assertTrue(db.saveBooks(books,null,0,0));DocumentLocator p=DocumentLocator.comic("cbr","aa".repeat(32),"bb".repeat(32),2,4,.5000005);db.saveDocumentPosition(comic,p,"ef".repeat(32),999);assertTrue(db.addDocumentBookmark(4,p));assertFalse(db.addDocumentBookmark(4,p));db.close();db=LocalDatabase.open(context,prefs);
        assertEquals(p,db.loadBooks().get(0).locator);assertEquals(p,db.documentBookmarks(4).get(0).locator);db.deleteBook(comic);assertTrue(db.documentBookmarks(4).isEmpty());assertEquals(1,db.documentBookmarks(2).size());assertEquals(1,db.loadBookmarks(1).size());assertEquals(1,android.database.DatabaseUtils.longForQuery(db.getReadableDatabase(),"pragma foreign_keys",null));
    }
    @Test public void invalidOldRowRollsBackMigrationAndRetainsOriginalDatabase()throws Exception {
        seedV3();try(SQLiteDatabase raw=SQLiteDatabase.openDatabase(context.getDatabasePath("xlib.db").getPath(),null,SQLiteDatabase.OPEN_READWRITE)){raw.execSQL("pragma ignore_check_constraints=ON");raw.execSQL("update books set format='future' where local_id='2'");}
        assertThrows(Exception.class,()->LocalDatabase.open(context,prefs));
        try(SQLiteDatabase raw=SQLiteDatabase.openDatabase(context.getDatabasePath("xlib.db").getPath(),null,SQLiteDatabase.OPEN_READWRITE)){assertEquals(3,raw.getVersion());assertEquals("future",android.database.DatabaseUtils.stringForQuery(raw,"select format from books where local_id='2'",null));assertEquals(2,android.database.DatabaseUtils.longForQuery(raw,"select count(*) from document_bookmarks",null));try(Cursor c=raw.rawQuery("select profile from document_positions",null)){fail("v4 migration must have rolled back");}catch(SQLiteException expected){}}
    }
    @Test public void missingOriginalAndUnknownLocatorAreRetainedAcrossLibrarySave()throws Exception {
        db=LocalDatabase.open(context,prefs);Book comic=book(5,"cbz"),txt=book(6,"txt");assertTrue(db.saveBooks(Arrays.asList(comic,txt),null,0,0));DocumentLocator p=DocumentLocator.comic("cbz","aa".repeat(32),"bb".repeat(32),1,3,0);db.saveDocumentPosition(comic,p,"cd".repeat(32),321);assertTrue(db.addDocumentBookmark(5,p));long modified=new File(comic.path).lastModified();new File(comic.path).delete();
        db.getWritableDatabase().execSQL("update document_positions set profile='comic-order-v9' where book_id='5'");List<Book> books=db.loadBooks();assertEquals(2,books.size());assertTrue(books.get(0).locatorUnavailable);assertTrue(db.saveBooks(books,null,0,0));assertEquals(1,db.documentBookmarks(5).size());assertEquals(modified,android.database.DatabaseUtils.longForQuery(db.getReadableDatabase(),"select source_modified_at_ms from books where local_id='5'",null));assertEquals("comic-order-v9|321|\n",rows(db.getReadableDatabase(),"document_positions","profile,read_at_ms"));
    }
}
