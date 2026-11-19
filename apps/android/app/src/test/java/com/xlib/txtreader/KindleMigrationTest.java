package com.xlib.txtreader;
import static org.junit.Assert.*;
import android.content.*;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.*;
import java.util.*;

@RunWith(RobolectricTestRunner.class) @Config(sdk=35)
public class KindleMigrationTest {
    final Context context=RuntimeEnvironment.getApplication();LocalDatabase db;
    @Before public void prepare(){context.deleteDatabase("xlib.db");context.getSharedPreferences("xlib_reader",0).edit().clear().commit();}
    @After public void close(){if(db!=null)db.close();context.deleteDatabase("xlib.db");}
    Book book(long id,String format)throws Exception{File directory=new File(context.getFilesDir(),"books");directory.mkdirs();File file=new File(directory,"kindle-migration-"+id);try(OutputStream output=new FileOutputStream(file)){output.write(1);}Book b=new Book();b.id=id;b.title=b.sourceName="old";b.path=file.getPath();b.format=format;b.encoding="UTF-8";b.fileSize=1;return b;}
    String rows(SQLiteDatabase sql,String table,String columns){StringBuilder out=new StringBuilder();try(Cursor c=sql.rawQuery("select "+columns+" from "+table+" order by 1",null)){while(c.moveToNext()){for(int i=0;i<c.getColumnCount();i++)out.append(c.isNull(i)?"<null>":c.getString(i)).append('|');out.append('\n');}}return out.toString();}
    @Test public void v4ToV5CopiesEveryColumnAndRestoresTypedKindleBookmarks()throws Exception {
        SharedPreferences prefs=context.getSharedPreferences("xlib_reader",0);db=LocalDatabase.open(context,prefs);
        Book pdf=book(901,"pdf"),comic=book(902,"cbz");assertTrue(db.saveBooks(Arrays.asList(pdf,comic),null,0,0));
        DocumentLocator position=DocumentLocator.comic("cbz","aa".repeat(32),"bb".repeat(32),1,4,.45);db.saveDocumentPosition(comic,position,"cc".repeat(32),777);assertTrue(db.addDocumentBookmark(comic.id,position));
        db.close();db=null;Map<String,String> before=new HashMap<>(),columns=new HashMap<>();
        try(SQLiteDatabase raw=SQLiteDatabase.openDatabase(context.getDatabasePath("xlib.db").getPath(),null,SQLiteDatabase.OPEN_READWRITE)){
            raw.setForeignKeyConstraintsEnabled(false);for(String table:new String[]{"document_positions","document_bookmarks"})raw.execSQL("alter table "+table+" drop column text_hash");raw.setVersion(4);
            for(String table:new String[]{"books","document_positions","document_bookmarks","settings","reading_progress","bookmarks"}){StringBuilder names=new StringBuilder();try(Cursor c=raw.rawQuery("pragma table_info("+table+")",null)){while(c.moveToNext()){if(names.length()>0)names.append(',');names.append(c.getString(1));}}columns.put(table,names.toString());before.put(table,rows(raw,table,names.toString()));}
        }
        db=LocalDatabase.open(context,prefs);assertEquals(5,db.getReadableDatabase().getVersion());for(String table:before.keySet())assertEquals(table,before.get(table),rows(db.getReadableDatabase(),table,columns.get(table)));
        Book kindle=book(903,"kindle");List<Book> books=db.loadBooks();books.add(kindle);assertTrue(db.saveBooks(books,null,0,0));DocumentLocator loc=DocumentLocator.kindle("dd".repeat(32),20,40);db.saveDocumentPosition(kindle,loc,"ee".repeat(32),1234);assertTrue(db.addDocumentBookmark(kindle.id,loc));assertFalse(db.addDocumentBookmark(kindle.id,loc));
        db.close();db=LocalDatabase.open(context,prefs);Book restored=db.loadBooks().get(0);assertEquals(kindle.id,restored.id);assertEquals(loc,restored.locator);assertEquals(1234,restored.updatedAt);assertEquals(loc,db.documentBookmarks(kindle.id).get(0).locator);
        db.getWritableDatabase().execSQL("update document_positions set profile='kindle-text-v9' where book_id='903'");assertTrue(db.loadBooks().get(0).locatorUnavailable);assertEquals(loc,db.documentBookmarks(kindle.id).get(0).locator);assertTrue(db.saveBooks(db.loadBooks(),null,0,0));
        try(Cursor c=db.getReadableDatabase().rawQuery("pragma foreign_key_check",null)){assertFalse(c.moveToFirst());}
    }
}
