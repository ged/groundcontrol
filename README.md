# symphony

home
: https://hg.sr.ht/~ged/symphony

docs
: https://deveiate.org/code/symphony

github
: https://github.com/ged/symphony


## Description

Symphony is a subscription-based asynchronous job system. It
allows you to define jobs that watch for lightweight events from a
distributed-messaging AMQP broker, and do work based on their payload.

It includes several executables under bin/:

symphony::
  A daemon which manages startup and shutdown of one or more Workers
  running Tasks as they are published from a queue.

symphony-task::
  A wrapper that runs a single task, useful for testing, or if you don't
  require the process management that the symphony daemon provides.


## Synopsis

	class WorkerTask < Symphony::Task
		# Process all events
		subscribe_to '#'

		def work( payload, metadata )
			puts "I got a payload! %p" % [ payload ]
			return true
		end
	end


For a more detailed description of usage, please refer to the USAGE document.


## Installation

    gem install symphony


## Contributing

You can check out the current development source with Mercurial via its
[project page](https://hg.sr.ht/~ged/symphony). Or if you prefer Git, via
[its Github mirror](https://github.com/ged/symphony).

After checking out the source, run:

    $ rake setup

This task will install dependencies, and do any other necessary developer setup.


## Authors

- Michael Granger <ged@faeriemud.org>
- Mahlon E. Smith <mahlon@martini.nu>


## License

Copyright (c) 2011-2020, Michael Granger and Mahlon E. Smith
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the author/s, nor the names of the project's
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


