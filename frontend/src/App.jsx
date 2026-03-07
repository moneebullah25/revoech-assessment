import { useState, useEffect } from 'react'

const API = 'http://localhost:8000'

function App() {
  const [fruits, setFruits] = useState([])
  const [color, setColor] = useState('')
  const [inSeason, setInSeason] = useState('')

  useEffect(() => {
    const qs = new URLSearchParams()
    if (color) qs.set('color', color)
    if (inSeason !== '') qs.set('in_season', inSeason)
    fetch(`${API}/fruit?${qs}`)
      .then(r => r.json())
      .then(setFruits)
      .catch(console.error)
  }, [color, inSeason])

  return (
    <div>
      <h1>Fruit List</h1>
      <div>
        <label>Color: <input value={color} onChange={e => setColor(e.target.value)} /></label>
        {' '}
        <label>In Season:
          <select value={inSeason} onChange={e => setInSeason(e.target.value)}>
            <option value="">All</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </label>
      </div>
      <ul>
        {fruits.map(f => (
          <li key={f.name}>
            <strong>{f.name}</strong> — {f.color} — {f.in_season ? 'In Season' : 'Out of Season'}
          </li>
        ))}
      </ul>
    </div>
  )
}

export default App
