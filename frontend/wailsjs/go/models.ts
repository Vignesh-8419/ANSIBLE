export namespace database {
	
	export class Record {
	    id: number;
	    hostname: string;
	    ip: string;
	    type: string;
	    ttl: number;
	
	    static createFrom(source: any = {}) {
	        return new Record(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.hostname = source["hostname"];
	        this.ip = source["ip"];
	        this.type = source["type"];
	        this.ttl = source["ttl"];
	    }
	}

}

