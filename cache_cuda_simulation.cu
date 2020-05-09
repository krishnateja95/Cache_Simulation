#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <unistd.h>

/************************************************************************/

__host__ int read_trace_element(FILE *infile, unsigned *access_type, unsigned *addr)
{
  int result;
  char c;

  result = fscanf(inFile, "%u %x%c", access_type, addr, &c);
  while (c != '\n') {
    result = fscanf(inFile, "%c", &c);
    if (result == EOF) 
      break;
  }
  if (result != EOF)
    return(1);
  else
    return(0);
}

/*************************************************************************/

__global__ void init_arrays(int *cache, int *two_cache, unsigned *cache_tag, unsigned *two_cache_tag, int *valid_bit, int *two_valid_bit, int *dirty_bit, int *two_dirty_bit, int *lru_counter, int* h_lru_count)
{
	if(threadIdx < 512)
	{
	 cache[threadIdx]=0;
	 two_cache[threadIdx]=0;
     cache_tag[threadIdx]=0;
	 two_cache_tag[threadIdx]=0;
     valid_bit[threadIdx]=0;
	 two_valid_bit[threadIdx]=0;
     dirty_bit[threadIdx]=0;
	 two_dirty_bit[threadIdx]=0;	

	 if((threadIdx%2)==0)
		lru_counter[threadIdx]=2;
	 else
		lru_counter[threadIdx]=1;	 
 
	 if(threadIdx<256)
		 h_lru_count[threadIdx] = 2;
	}	
}

/*************************************************************************/

__global__ void read_hit(unsigned *two_way_tag, unsigned *two_cache_tag, int *two_way_index, int *two_valid_bit, int *two_cache_read_hit, int *found, int *temp_lru, int *lru_counter, int *temp_index)
{
	if ((two_way_tag == two_cache_tag[(two_way_index << 1) | a]) && two_valid_bit[(two_way_index << 1) | a]) // the address tag matches cache tag and data is valid, i.e it is what we want
				{			
					two_cache_read_hit++;// then its a hit
					found = 1; // data was found
					// processor uses that data
					temp_lru = lru_counter[(two_way_index << 1) | threadIdx.x]; // keeping track of the lru value of the location which was operated on
					
					temp_index = (two_way_index << 1) | threadIdx.x; // keeping track of the location which was operated on		
				}	
}

__global__ void read_miss_empty(int *two_cache, int *two_way_index, unsigned *two_cache_tag, int *two_valid_bit, int *two_dirty_bit, int *lru_counter, int* h_lru_count, int *temp_lru, int *temp_index, int *data, unsigned *two_way_tag)
{
	if(two_cache[(two_way_index << 1) | threadIdx.x] == 0 && lru_counter[(two_way_index << 1) | threadIdx.x] == h_lru_count[two_way_index]) // place it in empty spot with highest LRU count for empty spot							
						{
							two_cache[(two_way_index << 1) | threadIdx.x] = data; // get the value from memory and store it in location with highest lru value for empty spot
							
							two_cache_tag[(two_way_index << 1) | threadIdx.x] = two_way_tag; // update the tag in cache
							
							two_valid_bit[(two_way_index << 1) | threadIdx.x] = 1; // set the valid bit to 1 as its the first time value is loaded in cache
							
							two_dirty_bit[(two_way_index << 1) | threadIdx.x] = 0; // setting dirty bit to 0 as new value was loaded into cache from memory
							
							h_lru_count[two_way_index]--; // the highest lru count for an empty spot is now decreased by 1
							
							temp_lru = lru_counter[(two_way_index << 1) | threadIdx.x]; // keeping track of the lru value of the location which was operated on
							
							temp_index = (two_way_index << 1) | threadIdx.x; // keeping track of the location which was operated on
							
						}	
	
}

__global__ void read_miss_full(int *two_cache, int *two_way_index, unsigned *two_cache_tag, int *two_valid_bit, int *two_dirty_bit, int *lru_counter, int* h_lru_count, int *temp_lru, int *temp_index, int *data, unsigned *two_way_tag)
{
	if (lru_counter[(two_way_index << 1) | threadIdx.x]==1) // check for location which was least recently used
						{
							
							two_cache[(two_way_index << 1) | threadIdx.x] = data; // replace the location which was least recently used with data from memory
							
							two_cache_tag[(two_way_index << 1) | threadIdx.x] = two_way_tag; // update the tag in cache
							
							temp_lru = lru_counter[(two_way_index << 1) | threadIdx.x]; // keeping track of the lru value of the location which was operated on
							
							temp_index = (two_way_index << 1) | threadIdx.x; // keeping track of the location which was operated on
							
							two_dirty_bit[(two_way_index << 1) | threadIdx.x] = 0; // setting dirty bit to 0 as new value was loaded into cache from memory
							
							two_valid_bit[(two_way_index << 1) | threadIdx.x] = 1; // data in cache is valid
							
						}
	
}

__global__ void write_hit(unsigned *two_way_tag, unsigned *two_cache_tag, int *two_way_index, int *two_valid_bit, int *two_cache_write_hit, int *w_found, int *temp_lru, int *lru_counter, int *temp_index, int *data)
{
	if((two_cache_tag[(two_way_index << 1) | threadIdx.x] == two_way_tag) && (two_valid_bit[(two_way_index << 1) | threadIdx.x] == 1))  // seeing if the location we wanna write to (we know this from tag) is already present 
			  {
				  w_found = 1; // we found it
				  two_cache_write_hit++;
				    
				  two_valid_bit[(two_way_index << 1) | threadIdx.x] = 1; 
				  
				  if(two_cache[(two_way_index << 1) | threadIdx.x] != data) // if the data sent by processor is new, i.e not same as one found for that tag
				  {
					  two_cache[(two_way_index << 1) | threadIdx.x] = data; // write new data in cache
					  two_dirty_bit[(two_way_index << 1) | threadIdx.x] = 1; // set dirty bit to one as new data was found
				  }
				  else
				  { 
					two_dirty_bit[(two_way_index << 1) | threadIdx.x] = 0; // if processor didn't provide new data, set dirty bit to 0
				  }
				  
				temp_lru = lru_counter[(two_way_index << 1) | threadIdx.x]; // keeping track of the lru value of the location which was operated on
				
				temp_index = (two_way_index << 1) | threadIdx.x; // keeping track of the location which was operated on						

				
			  }
	
}

__global__ void write_miss_empty(int *two_cache, int *two_way_index, unsigned *two_cache_tag, int *two_valid_bit, int *two_dirty_bit, int *lru_counter, int* h_lru_count, int *temp_lru, int *temp_index, int *data, unsigned *two_way_tag)
{
	if(two_cache[(two_way_index << 1) | threadIdx.x]==0 && lru_counter[(two_way_index << 1) | threadIdx.x] == h_lru_count[two_way_index]) // we search for an empty location with highest LRU count for an empty spot
					{
						two_cache[(two_way_index << 1) | threadIdx.x] = data; // load the new data given by processor in cache
						
						
						two_cache_tag[(two_way_index << 1) | threadIdx.x] = two_way_tag; // update the tag in cache
						
						two_valid_bit[(two_way_index << 1) | threadIdx.x] = 1; // set the valid bit to 1 as its the first time value is loaded in cache
						
						two_dirty_bit[(two_way_index << 1) | threadIdx.x] = 0; // setting dirty bit to 0 as value loaded in cache was just loaded in memory too
						
						h_lru_count[two_way_index]--; // the highest lru count for an empty spot is now decreased by 1
						
						temp_lru = lru_counter[(two_way_index << 1) | threadIdx.x]; // keeping track of the lru value of the location which was operated on
						
						temp_index = (two_way_index << 1) | threadIdx.x; // keeping track of the location which was operated on
				
					}
	
}

__global__ void write_miss_full(int *two_cache, int *two_way_index, unsigned *two_cache_tag, int *two_valid_bit, int *two_dirty_bit, int *lru_counter, int* h_lru_count, int *temp_lru, int *temp_index, int *data, unsigned *two_way_tag)
{
			if (lru_counter[(two_way_index << 1) | a] == 1) // check for location which was least recently used
							{
								
								two_cache[(two_way_index << 1) | a] = data; // replace the location which was least recently used with data from processor
								
								two_cache_tag[(two_way_index << 1) | a] = two_way_tag; // update the tag in cache
								
								temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
								
								temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
								
								two_dirty_bit[(two_way_index << 1) | a] = 0; // setting dirty bit to 0 as the value loaded in cache was also just loaded in memory
								
								two_valid_bit[(two_way_index << 1) | a] = 1; // the data is valid
								
								
							}
	
}

__global__ void lru_count(int *lru_counter, int *two_way_index, int *temp_lru)
{
	if(lru_counter[(two_way_index << 1) | threadIdx.x] > temp_lru) // if any lru value is greater than the value of location operated upon
					lru_counter[(two_way_index << 1) | threadIdx.x]--; // decrement it
	
}

/***************************************************************/

int main(int argc, char** argv)
{

	srand(time(0));
	  
	FILE *trace_file;
	  
	trace_file = fopen(argv[1], "r");
	  
	unsigned address, read;
	  
	int d_mask = 0x1ff;

	int two_mask = 0xff;

	int  cache_read_hit = 0, cache_read_miss = 0,cache_write_miss = 0,cache_write_hit = 0,i,n,j=0; 

	int  two_cache_read_hit = 0, two_cache_read_miss = 0, two_cache_write_miss = 0, two_cache_write_hit = 0;
	
	int *dev_two_cache_read_hit, *dev_two_cache_write_hit;

	int cache[512], two_cache[512];

	int *dev_cache, *dev_two_cache;

	int data;
	
	int *dev_data;

	unsigned two_cache_tag[512],cache_tag[512];

	unsigned *dev_two_cache_tag, *dev_cache_tag;

	int valid_bit[512], dirty_bit[512], two_valid_bit[512], two_dirty_bit[512];

	int *dev_valid_bit, *dev_dirty_bit, *dev_two_valid_bit, *dev_two_dirty_bit;

	unsigned two_way_tag, direct_mapped_tag;

	unsigned *dev_two_way_tag;

	int two_way_index, direct_mapped_index;

	int *dev_two_way_index;

	int lru_counter[512], h_lru_count[256];

	int *dev_lru_counter, *dev_h_lru_count;

	int a;

	int found, w_found;
	
	int *dev_found, *dev_w_found;

	int temp_lru, temp_index;

	int *dev_temp_lru, *dev_temp_index;


	/* for(a=0;a<512;a++)
	   {
		 cache[a]=0;
		 two_cache[a]=0;
		 cache_tag[a]=0;
		 two_cache_tag[a]=0;
		 valid_bit[a]=0;
		 two_valid_bit[a]=0;
		 dirty_bit[a]=0;
		 two_dirty_bit[a]=0;	

		 if((a%2)==0)
			lru_counter[a]=2;
		 else
			lru_counter[a]=1;	 
	 
		 if(a<256)
			 h_lru_count[a] = 2;
	   }
	 */
 
 cudaMalloc((void**)&dev_cache, 512*sizeof(int));
 cudaMalloc((void**)&dev_two_cache, 512*sizeof(int));
 cudaMalloc((void**)&dev_cache_tag, 512*sizeof(unsigned));
 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
 cudaMalloc((void**)&dev_valid_bit, 512*sizeof(int));
 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
 cudaMalloc((void**)&dev_dirty_bit, 512*sizeof(int));
 cudaMalloc((void**)&dev_two_dirty_bit, 512*sizeof(int));
 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
 cudaMalloc((void**)&dev_h_lru_count, 256*sizeof(int));
 
 cudaMemcpy(dev_cache, cache, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_two_cache, two_cache, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_cache_tag, cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_valid_bit, valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_dirty_bit, dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_two_dirty_bit, two_dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
 cudaMemcpy(dev_h_lru_count, h_lru_count, 256*sizeof(int), cudaMemcpyHostToDevice);
 
 init_arrays<<<1,512>>>(dev_cache, dev_two_cache, dev_cache_tag, dev_two_cache_tag, dev_valid_bit, dev_two_valid_bit, dev_dirty_bit, dev_two_dirty_bit, dev_lru_counter, dev_h_lru_count);
 
 cudaMemcpy(cache, dev_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(two_cache, dev_two_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(cache_tag, dev_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
 cudaMemcpy(valid_bit, dev_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(dirty_bit, dev_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(two_dirty_bit, dev_two_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
 cudaMemcpy(h_lru_count, dev_h_lru_count, 256*sizeof(int), cudaMemcpyDeviceToHost);
 
 cudaFree(dev_cache);
 cudaFree(dev_two_cache);
 cudaFree(dev_cache_tag);
 cudaFree(dev_two_cache_tag);
 cudaFree(dev_valid_bit);
 cudaFree(dev_two_valid_bit);
 cudaFree(dev_dirty_bit);
 cudaFree(dev_two_dirty_bit);
 cudaFree(dev_lru_counter);
 cudaFree(dev_h_lru_count);
 
while(read_trace_element(trace_file, &read, &address))
	{	 
		if(read == 0 || read == 2)
			read = 1; // reading if read was zero or two as per trace
		else
			read = 0; // writing if read was 1 as per trace

		 data = (rand()%100)+1;

	//Direct Mapped
	
		direct_mapped_index = (address >> 4) & d_mask;
		direct_mapped_tag = address >> 13;
		
		

		if(read)
		{

			if((direct_mapped_tag == cache_tag[direct_mapped_index]) && valid_bit[direct_mapped_index]) // the address tag matches cache tag and data is valid, i.e it is what we want
			{
				
				cache_read_hit++;// then its a hit

			// processor uses that data

			}
			else // if its a miss
			{
		
				 cache_read_miss++;

				 cache[direct_mapped_index] = data; // data loaded from main memory into cache

				 valid_bit[direct_mapped_index] = 1; // now that data is loaded from main memory, valid bit becomes 1 
				 
				 dirty_bit[direct_mapped_index] = 0; // since a fresh data is loaded from main memory, dirty bit is 0;

				 cache_tag[direct_mapped_index] = direct_mapped_tag; // tag is updated in cache with new address' tag

				 // processor uses that data

			}

		}
		else // write statements go over here  
		 //we're implementing write-back and write allocate
		{
			 if(direct_mapped_tag == cache_tag[direct_mapped_index] && valid_bit[direct_mapped_index]) // checking the tag of address to be written to is same as what processor provided 
			   {
					if(cache[direct_mapped_index] != data) // if the data sent by processor is not same as the one already present in that cache location
					{
						 dirty_bit[direct_mapped_index] = 1; // change dirty bit to 1
						 cache[direct_mapped_index] = data; // write the new data in cache
					}
					else					
					{
						dirty_bit[direct_mapped_index] = 0; // if data is already there then dirty bit is 0 since  no change was done
					}
					valid_bit[direct_mapped_index] = 1; // now that we have valid data, the valid bit is 1
					
					cache_write_hit++;
			   }
			 else // its a write miss
			   {
			 

					 cache[direct_mapped_index] = data; // write new data to cache 
					 
					 cache_tag[direct_mapped_index] = direct_mapped_tag; // update the cache with new tag

					 dirty_bit[direct_mapped_index] = 0; // dirty bit is 0 as this is the first time we have the new value from write operation but we put that value in memory just now

					 valid_bit[direct_mapped_index] = 1; // now that valid data is in cache, valid bit becomes 1 
					 
					 cache_write_miss++;
					}

		}
			
		
		two_way_index = (address >> 4)& two_mask;
		two_way_tag = address >> 12;
		
		// 2 way set associative
		
		if(read)
		{	
			found = 0;	
		/*	for(a = 0; a < 2; a++) // going to appropriate set and looping through
			{
				if ((two_way_tag == two_cache_tag[(two_way_index << 1) | a]) && two_valid_bit[(two_way_index << 1) | a]) // the address tag matches cache tag and data is valid, i.e it is what we want
				{
					
					two_cache_read_hit++;// then its a hit
					found = 1; // data was found
					// processor uses that data
					temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
					
					temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
					
					break;
				}	
			} */
			
			 
			 cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
			 cudaMalloc((void**)&dev_two_cache_read_hit, sizeof(int));
			 cudaMalloc((void**)&dev_found, sizeof(int));
			 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
			 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
			 cudaMalloc((void**)&dev_temp_index, sizeof(int));
			
			 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_cache_read_hit, two_cache_read_hit, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_found, found, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
						
			read_hit<<<1,2>>>(dev_two_way_tag, dev_two_cache_tag, dev_two_way_index, dev_two_valid_bit, dev_two_cache_read_hit, dev_found, dev_temp_lru, dev_lru_counter, dev_temp_index);
			
			 cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_cache_read_hit, dev_two_cache_read_hit,  sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(found, dev_found, sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
			 
			 cudaFree(dev_two_way_tag);
			 cudaFree(dev_two_cache_tag);
			 cudaFree(dev_two_way_index);
			 cudaFree(dev_two_valid_bit);
			 cudaFree(dev_two_cache_read_hit);
			 cudaFree(dev_found);
			 cudaFree(dev_temp_lru);
			 cudaFree(dev_lru_counter);
			 cudaFree(dev_temp_index);
			
			if(!found)  // if its a miss
			{
				two_cache_read_miss++;
			/*	for(a=0;a<2;a++)  // we see if any locations in the set were empty
				{
					if(two_cache[(two_way_index << 1) | a] == 0 && lru_counter[(two_way_index << 1) | a] == h_lru_count[two_way_index]) // place it in empty spot with highest LRU count for empty spot							
						{
							two_cache[(two_way_index << 1) | a] = data; // get the value from memory and store it in location with highest lru value for empty spot
							
							two_cache_tag[(two_way_index << 1) | a] = two_way_tag; // update the tag in cache
							
							two_valid_bit[(two_way_index << 1) | a] = 1; // set the valid bit to 1 as its the first time value is loaded in cache
							
							two_dirty_bit[(two_way_index << 1) | a] = 0; // setting dirty bit to 0 as new value was loaded into cache from memory
							
							h_lru_count[two_way_index]--; // the highest lru count for an empty spot is now decreased by 1
							
							temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
							
							temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
							
							break; // exiting the loop when our goal was achieved
						}	
				}  */
				
				 cudaMalloc((void**)&dev_two_cache, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_dirty_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
				 cudaMalloc((void**)&dev_h_lru_count, 256*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
				 cudaMalloc((void**)&dev_data, sizeof(int));
				 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
				 cudaMalloc((void**)&dev_temp_index, sizeof(int));
				 
	
				 cudaMemcpy(dev_two_cache, two_cache, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_dirty_bit, two_dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_h_lru_count, h_lru_count, 256*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_data, data, sizeof(int), cudaMemcpyHostToDevice);			 
				 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
					 				 
												
				read_miss_empty<<<1,2>>>(dev_two_cache, dev_two_way_index, dev_two_cache_tag, dev_two_valid_bit, dev_two_dirty_bit, dev_lru_counter, dev_h_lru_count, dev_temp_lru, dev_temp_index, dev_data, two_way_tag);
				
				 
				 cudaMemcpy(two_cache, dev_two_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_dirty_bit, dev_two_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(h_lru_count, dev_h_lru_count, 256*sizeof(int), cudaMemcpyDeviceToHost);				
				 cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(data, dev_data, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
					
				cudaFree(dev_two_cache);
				cudaFree(dev_two_way_index);
				cudaFree(dev_two_cache_tag);
				cudaFree(dev_two_valid_bit);
				cudaFree(dev_two_dirty_bit);
				cudaFree(dev_lru_counter);
				cudaFree(dev_h_lru_count);
				cudaFree(dev_temp_lru);
				cudaFree(dev_temp_index);
				cudaFree(dev_data);
				cudaFree(dev_two_way_tag);
				
				if(h_lru_count[two_way_index] == 0) // when set is no longer empty
				{
					
				/*	for(a=0;a<2;a++) // we want to see which location in set has to be replaced
					{
						if (lru_counter[(two_way_index << 1) | a]==1) // check for location which was least recently used
						{
							
							two_cache[(two_way_index << 1) | a] = data; // replace the location which was least recently used with data from memory
							
							two_cache_tag[(two_way_index << 1) | a] = two_way_tag; // update the tag in cache
							
							temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
							
							temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
							
							two_dirty_bit[(two_way_index << 1) | a] = 0; // setting dirty bit to 0 as new value was loaded into cache from memory
							
							two_valid_bit[(two_way_index << 1) | a] = 1; // data in cache is valid
							
							break; // exiting the loop when our goal was achieved
						}
					} */
					
					
				 cudaMalloc((void**)&dev_two_cache, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_dirty_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
				 
				 cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
				 cudaMalloc((void**)&dev_data, sizeof(int));
				 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
				 cudaMalloc((void**)&dev_temp_index, sizeof(int));
				 
	
				 cudaMemcpy(dev_two_cache, two_cache, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_dirty_bit, two_dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_data, data, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
					 
					
					read_miss_full<<<1,2>>>(dev_two_cache, dev_two_way_index, dev_two_cache_tag, dev_two_valid_bit, dev_two_dirty_bit, dev_lru_counter, dev_temp_lru, dev_temp_index, dev_data, two_way_tag);
					
					 cudaMemcpy(two_cache, dev_two_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_dirty_bit, dev_two_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 			
				 cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(data, dev_data, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
					
				cudaFree(dev_two_cache);
				cudaFree(dev_two_way_index);
				cudaFree(dev_two_cache_tag);
				cudaFree(dev_two_valid_bit);
				cudaFree(dev_two_dirty_bit);
				cudaFree(dev_lru_counter);
				cudaFree(dev_temp_lru);
				cudaFree(dev_temp_index);
				cudaFree(dev_data);
				cudaFree(dev_two_way_tag);
					
				}
				
			}	
			
		}
		else // write statements go over here  
		 //we're implementing write-back and write allocate
		{
			
		  w_found=0;
		  
		/*  for(a=0;a<2;a++) // looping through the set 
		  {
			  if((two_cache_tag[(two_way_index << 1) | a] == two_way_tag) && (two_valid_bit[(two_way_index << 1) | a] == 1))  // seeing if the location we wanna write to (we know this from tag) is already present 
			  {
				  w_found = 1; // we found it
				  two_cache_write_hit++;
				    
				  two_valid_bit[(two_way_index << 1) | a] = 1; 
				  
				  if(two_cache[(two_way_index << 1) | a] != data) // if the data sent by processor is new, i.e not same as one found for that tag
				  {
					  two_cache[(two_way_index << 1) | a] = data; // write new data in cache
					  two_dirty_bit[(two_way_index << 1) | a] = 1; // set dirty bit to one as new data was found
				  }
				  else
				  { 
					two_dirty_bit[(two_way_index << 1) | a] = 0; // if processor didn't provide new data, set dirty bit to 0
				  }
				  
				temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
				
				temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on						

				break;	
			  }
		  }  */
		  
		  cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
			 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
			 cudaMalloc((void**)&dev_two_cache_read_hit, sizeof(int));
			 cudaMalloc((void**)&dev_w_found, sizeof(int));
			 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
			 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
			 cudaMalloc((void**)&dev_temp_index, sizeof(int));
			 cudaMalloc((void**)&dev_data, sizeof(int));
			
			 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_two_cache_read_hit, two_cache_read_hit, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_w_found, w_found, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
			 cudaMemcpy(dev_data, data, sizeof(int), cudaMemcpyHostToDevice);
		  
		  write_hit<<<1,2>>>(dev_two_way_tag, dev_two_cache_tag, dev_two_way_index, dev_two_valid_bit, dev_two_cache_write_hit, dev_w_found, dev_temp_lru, dev_lru_counter, dev_temp_index, dev_data);
		  
		   cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(two_cache_read_hit, dev_two_cache_read_hit,  sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(w_found, dev_w_found, sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
			 cudaMemcpy(data, dev_data, sizeof(int), cudaMemcpyDeviceToHost);
			 
			 cudaFree(dev_two_way_tag);
			 cudaFree(dev_two_cache_tag);
			 cudaFree(dev_two_way_index);
			 cudaFree(dev_two_valid_bit);
			 cudaFree(dev_two_cache_read_hit);
			 cudaFree(dev_w_found);
			 cudaFree(dev_temp_lru);
			 cudaFree(dev_lru_counter);
			 cudaFree(dev_temp_index);
			 cudaFree(dev_data);
			
		  
		  if(!w_found) // if that tag wasn't found, 
			  
			  {
				  two_cache_write_miss++;
				
				/*  for(a=0;a<2;a++) // loop through the set 
				  {
				  
					if(two_cache[(two_way_index << 1) | a]==0 && lru_counter[(two_way_index << 1) | a] == h_lru_count[two_way_index]) // we search for an empty location with highest LRU count for an empty spot
					{
						two_cache[(two_way_index << 1) | a] = data; // load the new data given by processor in cache
						
						
						two_cache_tag[(two_way_index << 1) | a] = two_way_tag; // update the tag in cache
						
						two_valid_bit[(two_way_index << 1) | a] = 1; // set the valid bit to 1 as its the first time value is loaded in cache
						
						two_dirty_bit[(two_way_index << 1) | a] = 0; // setting dirty bit to 0 as value loaded in cache was just loaded in memory too
						
						h_lru_count[two_way_index]--; // the highest lru count for an empty spot is now decreased by 1
						
						temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
						
						temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
						
						break; // exiting the loop when our goal was achieved
					}
				  } */
				  
				  
				   cudaMalloc((void**)&dev_two_cache, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_dirty_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
				 cudaMalloc((void**)&dev_h_lru_count, 256*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
				 cudaMalloc((void**)&dev_data, sizeof(int));
				 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
				 cudaMalloc((void**)&dev_temp_index, sizeof(int));
				 
	
				 cudaMemcpy(dev_two_cache, two_cache, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_dirty_bit, two_dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_h_lru_count, h_lru_count, 256*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_data, data, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
					 
				  
				  write_miss_empty<<<1,2>>>(dev_two_cache, dev_two_way_index, dev_two_cache_tag, dev_two_valid_bit, dev_two_dirty_bit, dev_lru_counter, dev_h_lru_count, dev_temp_lru, dev_temp_index, dev_data, two_way_tag);
				  
				  
				 cudaMemcpy(two_cache, dev_two_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_dirty_bit, dev_two_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(h_lru_count, dev_h_lru_count, 256*sizeof(int), cudaMemcpyDeviceToHost);				
				 cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(data, dev_data, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
					
				cudaFree(dev_two_cache);
				cudaFree(dev_two_way_index);
				cudaFree(dev_two_cache_tag);
				cudaFree(dev_two_valid_bit);
				cudaFree(dev_two_dirty_bit);
				cudaFree(dev_lru_counter);
				cudaFree(dev_h_lru_count);
				cudaFree(dev_temp_lru);
				cudaFree(dev_temp_index);
				cudaFree(dev_data);
				cudaFree(dev_two_way_tag);
				
				if(h_lru_count[two_way_index] == 0) //all the blocks are occupied
					{
							
					/*	for(a=0;a<2;a++) // we want to see which location in set has to be replaced
						{
							if (lru_counter[(two_way_index << 1) | a] == 1) // check for location which was least recently used
							{
								
								two_cache[(two_way_index << 1) | a] = data; // replace the location which was least recently used with data from processor
								
								two_cache_tag[(two_way_index << 1) | a] = two_way_tag; // update the tag in cache
								
								temp_lru = lru_counter[(two_way_index << 1) | a]; // keeping track of the lru value of the location which was operated on
								
								temp_index = (two_way_index << 1) | a; // keeping track of the location which was operated on
								
								two_dirty_bit[(two_way_index << 1) | a] = 0; // setting dirty bit to 0 as the value loaded in cache was also just loaded in memory
								
								two_valid_bit[(two_way_index << 1) | a] = 1; // the data is valid
								
								break; // exiting the loop when our goal was achieved
							}
						}  */
						
						
						 cudaMalloc((void**)&dev_two_cache, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_way_index, sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_cache_tag, 512*sizeof(unsigned));
				 cudaMalloc((void**)&dev_two_valid_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_two_dirty_bit, 512*sizeof(int));
				 cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
				 
				 cudaMalloc((void**)&dev_two_way_tag, sizeof(unsigned));
				 cudaMalloc((void**)&dev_data, sizeof(int));
				 cudaMalloc((void**)&dev_temp_lru, sizeof(int));
				 cudaMalloc((void**)&dev_temp_index, sizeof(int));
				 
	
				 cudaMemcpy(dev_two_cache, two_cache, 512*sizeof(int), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_cache_tag, two_cache_tag, 512*sizeof(unsigned), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_valid_bit, two_valid_bit, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_dirty_bit, two_dirty_bit, 512*sizeof(int), cudaMemcpyHostToDevice);
				 cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);				
				 cudaMemcpy(dev_two_way_tag, two_way_tag, sizeof(unsigned), cudaMemcpyHostToDevice);			
				 cudaMemcpy(dev_two_way_index, two_way_index, sizeof(unsigned), cudaMemcpyHostToDevice);			 
				 cudaMemcpy(dev_data, data, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);				 
				 cudaMemcpy(dev_temp_index, temp_index, sizeof(int), cudaMemcpyHostToDevice);
					 
					
						
						write_miss_full<<<1,2>>>(dev_two_cache, dev_two_way_index, dev_two_cache_tag, dev_two_valid_bit, dev_two_dirty_bit, dev_lru_counter, dev_temp_lru, dev_temp_index, dev_data, two_way_tag);
						
						 cudaMemcpy(two_cache, dev_two_cache, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_cache_tag, dev_two_cache_tag, 512*sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_valid_bit, dev_two_valid_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_dirty_bit, dev_two_dirty_bit, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
				 			
				 cudaMemcpy(two_way_tag, dev_two_way_tag, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(data, dev_data, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(two_way_index, dev_two_way_index, sizeof(unsigned), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
				 cudaMemcpy(temp_index, dev_temp_index, sizeof(int), cudaMemcpyDeviceToHost);
					
				cudaFree(dev_two_cache);
				cudaFree(dev_two_way_index);
				cudaFree(dev_two_cache_tag);
				cudaFree(dev_two_valid_bit);
				cudaFree(dev_two_dirty_bit);
				cudaFree(dev_lru_counter);
				cudaFree(dev_temp_lru);
				cudaFree(dev_temp_index);
				cudaFree(dev_data);
				cudaFree(dev_two_way_tag);
						
					}
			  }
									
		}
					
		/*	for(a=0;a<2;a++) // looping through the lru counters for the particular set for updating
				
			{
				if(lru_counter[(two_way_index << 1) | a] > temp_lru) // if any lru value is greater than the value of location operated upon
					lru_counter[(two_way_index << 1) | a]--; // decrement it by 1
			} */
			
			cudaMalloc((void**)&dev_lru_counter, 512*sizeof(int));
			cudaMalloc((void**)&dev_two_way_index, sizeof(int));
			cudaMalloc((void**)&dev_temp_lru, sizeof(int));
			
			cudaMemcpy(dev_lru_counter, lru_counter, 512*sizeof(int), cudaMemcpyHostToDevice);
			cudaMemcpy(dev_two_way_index, two_way_index, sizeof(int), cudaMemcpyHostToDevice);
			cudaMemcpy(dev_temp_lru, temp_lru, sizeof(int), cudaMemcpyHostToDevice);
			
			lru_count<<<1,2>>>(dev_lru_counter, dev_two_way_index, dev_temp_lru);
			
			cudaMemcpy(lru_counter, dev_lru_counter, 512*sizeof(int), cudaMemcpyDeviceToHost);
			cudaMemcpy(two_way_index, dev_two_way_index, sizeof(int), cudaMemcpyDeviceToHost);
			cudaMemcpy(temp_lru, dev_temp_lru, sizeof(int), cudaMemcpyDeviceToHost);
			
			cudaFree(dev_lru_counter);
			cudaFree(dev_two_way_index);
			cudaFree(dev_temp_lru);
			
			lru_counter[temp_index] = 2; // set the lru to be highest for the location which was just operated upon
		
			
			
			
			
   }
      
 printf(" The total cache read hits for direct mapped = %d \n",cache_read_hit); 
 printf(" The total cache read misses for direct mapped are = %d \n",cache_read_miss); 
 printf(" The total cache write hit for direct mapped are = %d \n",cache_write_hit); 
 printf(" The total cache write misses for direct mapped are = %d \n",cache_write_miss); 
 printf("\n");
 printf(" The total cache read hits for two way set associativity = %d \n",two_cache_read_hit); 
 printf(" The total cache read misses for two way set associativity = %d \n",two_cache_read_miss); 
 printf(" The total cache write hit for two way set associativity are = %d \n",two_cache_write_hit); 
 printf(" The total cache write misses for two way set associativity are = %d \n",two_cache_write_miss); 

return 0;
}

