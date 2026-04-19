import Foundation

func fetchAQ() async throws -> airquality{
    let apiKey = ""
    guard let baseurl = URL(string:"https://api.waqi.info/feed/here/?token=\(apiKey)") else{
        throw ErrorType.networkError
    }
    
    var request = URLRequest(url: baseurl)
    request.httpMethod = "GET"
    request.setValue("api key come soon", forHTTPHeaderField: "x-api-key")
    
    do{
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else{
            throw ErrorType.networkError
        }
        
        guard httpResponse.statusCode == 201 else {
            throw ErrorType.networkError
        }
        
        let decoder = JSONDecoder()
        
        do {
            let get = try decoder.decode(airquality.self, from: data)
            return get
        } catch {
            throw ErrorType.codingError
        }
        
    } catch is URLError{
        throw ErrorType.networkError
    } catch{
        throw ErrorType.unknown
    }
    
    //testing git ignore 
}
