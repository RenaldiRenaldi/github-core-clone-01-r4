// The static binary owns Git, HTTP, offline proof and the complete harness lifecycle.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const child=spawn(fileURLToPath(new URL('./forge',import.meta.url)),[],{stdio:'inherit',env:process.env});
child.once('error',error=>{console.error(error.message);process.exitCode=1});
child.once('exit',(code,signal)=>{process.exitCode=signal?1:(code??1)});
for(const signal of ['SIGTERM','SIGINT'] as const)process.once(signal,()=>child.kill(signal));
