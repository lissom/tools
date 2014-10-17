var allStats = []; 
db.getMongo().getDBNames().forEach(function (d) {
	var currDb = db.getSiblingDB(d);
    var dbStats = {};
    dbStats.database = d;
    dbStats.stats = currDb.stats();
    dbStats.collections = [];
    currDb.getCollectionNames().forEach(function(coll) {
    	if ( typeof c != "function") {
	    	var currColl = currDb.getCollection(coll);
	    	var collStats = {};
	    	collStats.name = coll; 
	    	collStats.stats = currColl.stats();
	    	collStats.indexDetails = currColl.getIndexes();  
	    	dbStats.collections.push(collStats);
        }
    });
	allStats.push(dbStats);    
});
printjson(allStats);

